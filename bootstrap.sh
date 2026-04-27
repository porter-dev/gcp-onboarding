#!/usr/bin/env bash
#
# Provisions the Porter integration in the current GCP project.
# Idempotent: safe to re-run if a previous attempt failed partway.
#
# Inputs (positional, or env):
#   PORTER_PROJECT_ID            $1
#   PORTER_TENANT_EXTERNAL_ID    $2
#   PORTER_AWS_ACCOUNT_ID        $3
#   PORTER_AWS_ROLE_NAME         $4 (optional, default: porter-ccp)
#
# Required environment variables (set by Porter via the Cloud Shell deeplink):
#   PORTER_INTEGRATION_ID        UUID of the cloud_account row
#   PORTER_VERIFICATION_TOKEN    Single-use bearer token for the bootstrap callback
#   PORTER_API_URL               Base URL of the Porter API (e.g. https://api.porter.run)
#   PORTER_PROJECT_ID_NUMERIC    Porter project ID (integer; distinct from PORTER_PROJECT_ID which is the GCP project)
#
set -euo pipefail

readonly script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<USAGE >&2
Usage: $0 <project_id> <tenant_external_id> <porter_aws_account_id> [porter_aws_role_name]

Or via environment variables:
  PORTER_PROJECT_ID, PORTER_TENANT_EXTERNAL_ID, PORTER_AWS_ACCOUNT_ID, [PORTER_AWS_ROLE_NAME]
USAGE
  exit 1
}

resolve_args() {
  project_id=${1:-${PORTER_PROJECT_ID:-}}
  tenant_external_id=${2:-${PORTER_TENANT_EXTERNAL_ID:-}}
  porter_aws_account_id=${3:-${PORTER_AWS_ACCOUNT_ID:-}}
  porter_aws_role_name=${4:-${PORTER_AWS_ROLE_NAME:-porter-ccp}}

  if [[ -z $project_id || -z $tenant_external_id || -z $porter_aws_account_id ]]; then
    usage
  fi
}

require_tool() {
  local tool=$1
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' is not installed or not in PATH" >&2
    exit 2
  fi
}

ensure_state_bucket() {
  local bucket=$1

  if gcloud storage buckets describe "gs://${bucket}" --project="${project_id}" --format='value(name)' >/dev/null 2>&1; then
    return
  fi

  echo "Creating Terraform state bucket gs://${bucket}..."
  gcloud storage buckets create "gs://${bucket}" \
    --project="${project_id}" \
    --location=us \
    --uniform-bucket-level-access \
    --public-access-prevention

  gcloud storage buckets update "gs://${bucket}" --versioning
}

run_terraform() {
  local bucket=$1
  local prefix=$2

  pushd "${script_dir}" >/dev/null

  terraform init \
    -input=false \
    -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${prefix}"

  terraform apply \
    -input=false \
    -auto-approve \
    -var "project_id=${project_id}" \
    -var "tenant_external_id=${tenant_external_id}" \
    -var "porter_aws_account_id=${porter_aws_account_id}" \
    -var "porter_aws_role_name=${porter_aws_role_name}"

  popd >/dev/null
}

print_done() {
  cat <<DONE

================================================================
Bootstrap complete.

Porter is now polling for federation in your dashboard. It will:
  1. Detect that federation works (a few seconds).
  2. Enable the remaining GCP APIs server-side.
  3. Grant the remaining IAM roles to porter-manager.
  4. Advance the dashboard to 100%.

You can close this tab now.
================================================================

DONE
}

notify_porter() {
  if [[ -z ${PORTER_API_URL:-} || -z ${PORTER_INTEGRATION_ID:-} || -z ${PORTER_VERIFICATION_TOKEN:-} || -z ${PORTER_PROJECT_ID_NUMERIC:-} ]]; then
    echo "warning: Porter callback env vars not set; skipping bootstrap callback." >&2
    echo "  Polling will stay at 0% until the project number is delivered." >&2
    return
  fi

  local project_number
  project_number=$(gcloud projects describe "${project_id}" --format='value(projectNumber)')
  if [[ -z $project_number ]]; then
    echo "error: failed to look up project number for ${project_id}" >&2
    exit 3
  fi

  local payload
  payload=$(cat <<JSON
{"porter_project_id":${PORTER_PROJECT_ID_NUMERIC},"gcp_project_number":"${project_number}","verification_token":"${PORTER_VERIFICATION_TOKEN}"}
JSON
)

  local url="${PORTER_API_URL%/}/api/v2/integrations/gcp/wif/${PORTER_INTEGRATION_ID}/bootstrap"
  echo "Notifying Porter at ${url}..."
  curl -sSf -X POST -H 'Content-Type: application/json' -d "${payload}" "${url}" >/dev/null
}

main() {
  resolve_args "$@"
  require_tool gcloud
  require_tool terraform
  require_tool curl

  local bucket="porter-tfstate-${project_id}"
  local prefix="gcp-onboarding/${tenant_external_id}"

  ensure_state_bucket "${bucket}"
  run_terraform "${bucket}" "${prefix}"
  notify_porter
  print_done
}

main "$@"
