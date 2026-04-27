#!/usr/bin/env bash
#
# Provisions the Porter integration in the current GCP project.
# Idempotent: safe to re-run if a previous attempt failed partway.
#
# All per-tenant configuration is fetched at runtime from Porter's API
# using the three values Porter sets in the Cloud Shell session via the
# setup command:
#
#   PORTER_API_URL              Base URL of the Porter API
#   PORTER_INTEGRATION_ID       UUID of the cloud_account row
#   PORTER_VERIFICATION_TOKEN   Single-use bearer token, validated by
#                               hash, consumed at the bootstrap callback
#
set -euo pipefail

readonly script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

require_tool() {
  local tool=$1
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' is not installed or not in PATH" >&2
    exit 2
  fi
}

require_env() {
  local name=$1
  if [[ -z ${!name:-} ]]; then
    echo "error: required env var $name is not set" >&2
    echo "  copy the setup command from the Porter dashboard and paste it." >&2
    exit 1
  fi
}

fetch_details() {
  local url="${PORTER_API_URL%/}/api/v2/integrations/gcp/wif/${PORTER_INTEGRATION_ID}/details"
  local payload
  payload=$(printf '{"verification_token":"%s"}' "${PORTER_VERIFICATION_TOKEN}")

  local response
  response=$(curl -sSf -X POST -H 'Content-Type: application/json' -d "${payload}" "${url}")

  gcp_project_id=$(jq -r '.gcp_project_id' <<<"${response}")
  tenant_external_id=$(jq -r '.tenant_external_id' <<<"${response}")
  porter_aws_account_id=$(jq -r '.porter_aws_account_id' <<<"${response}")
  porter_aws_role_name=$(jq -r '.porter_aws_role_name' <<<"${response}")

  if [[ -z $gcp_project_id || $gcp_project_id == null ||
        -z $tenant_external_id || $tenant_external_id == null ||
        -z $porter_aws_account_id || $porter_aws_account_id == null ||
        -z $porter_aws_role_name || $porter_aws_role_name == null ]]; then
    echo "error: Porter /details response missing required fields" >&2
    echo "  raw response: ${response}" >&2
    exit 3
  fi
}

ensure_state_bucket() {
  local bucket=$1

  if gcloud storage buckets describe "gs://${bucket}" --project="${gcp_project_id}" --format='value(name)' >/dev/null 2>&1; then
    return
  fi

  echo "Creating Terraform state bucket gs://${bucket}..."
  gcloud storage buckets create "gs://${bucket}" \
    --project="${gcp_project_id}" \
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
    -var "project_id=${gcp_project_id}" \
    -var "tenant_external_id=${tenant_external_id}" \
    -var "porter_aws_account_id=${porter_aws_account_id}" \
    -var "porter_aws_role_name=${porter_aws_role_name}"

  popd >/dev/null
}

notify_porter() {
  local project_number
  project_number=$(gcloud projects describe "${gcp_project_id}" --format='value(projectNumber)')
  if [[ -z $project_number ]]; then
    echo "error: failed to look up project number for ${gcp_project_id}" >&2
    exit 4
  fi

  local payload
  payload=$(printf '{"verification_token":"%s","gcp_project_number":"%s"}' \
    "${PORTER_VERIFICATION_TOKEN}" "${project_number}")

  local url="${PORTER_API_URL%/}/api/v2/integrations/gcp/wif/${PORTER_INTEGRATION_ID}/bootstrap"
  echo "Notifying Porter at ${url}..."
  curl -sSf -X POST -H 'Content-Type: application/json' -d "${payload}" "${url}" >/dev/null
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

main() {
  require_env PORTER_API_URL
  require_env PORTER_INTEGRATION_ID
  require_env PORTER_VERIFICATION_TOKEN

  require_tool gcloud
  require_tool terraform
  require_tool curl
  require_tool jq

  fetch_details

  local bucket="porter-tfstate-${gcp_project_id}"
  local prefix="gcp-onboarding/${tenant_external_id}"

  ensure_state_bucket "${bucket}"
  run_terraform "${bucket}" "${prefix}"
  notify_porter
  print_done
}

main "$@"
