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

print_outputs() {
  pushd "${script_dir}" >/dev/null

  local provider email
  provider=$(terraform output -raw workload_identity_provider)
  email=$(terraform output -raw service_account_email)

  cat <<DONE

================================================================
Porter is now connected to project ${project_id}.

Copy the two values below back into Porter:

  Workload Identity Provider:
  ${provider}

  Service Account Email:
  ${email}
================================================================

DONE

  popd >/dev/null
}

main() {
  resolve_args "$@"
  require_tool gcloud
  require_tool terraform

  local bucket="porter-tfstate-${project_id}"
  local prefix="gcp-onboarding/${tenant_external_id}"

  ensure_state_bucket "${bucket}"
  run_terraform "${bucket}" "${prefix}"
  print_outputs
}

main "$@"
