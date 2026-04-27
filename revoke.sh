#!/usr/bin/env bash
#
# Removes Porter's access from the current GCP project.
# Destroys the service account, Workload Identity Pool, and
# the API enablement records owned by this deployment's Terraform state.
#
# The state bucket itself is left in place so re-onboarding works without
# extra IAM. Pass --purge-state to also delete it.
#
set -euo pipefail

readonly script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<USAGE >&2
Usage: $0 <project_id> <tenant_external_id> <porter_aws_account_id> [porter_aws_role_name] [--purge-state]
USAGE
  exit 1
}

resolve_args() {
  purge_state=false
  positional=()

  for arg in "$@"; do
    case "$arg" in
      --purge-state) purge_state=true ;;
      *) positional+=("$arg") ;;
    esac
  done

  project_id=${positional[0]:-${PORTER_PROJECT_ID:-}}
  tenant_external_id=${positional[1]:-${PORTER_TENANT_EXTERNAL_ID:-}}
  porter_aws_account_id=${positional[2]:-${PORTER_AWS_ACCOUNT_ID:-}}
  porter_aws_role_name=${positional[3]:-${PORTER_AWS_ROLE_NAME:-porter-ccp}}

  if [[ -z $project_id || -z $tenant_external_id || -z $porter_aws_account_id ]]; then
    usage
  fi
}

run_terraform_destroy() {
  local bucket=$1
  local prefix=$2

  pushd "${script_dir}" >/dev/null

  terraform init \
    -input=false \
    -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${prefix}"

  terraform destroy \
    -input=false \
    -auto-approve \
    -var "project_id=${project_id}" \
    -var "tenant_external_id=${tenant_external_id}" \
    -var "porter_aws_account_id=${porter_aws_account_id}" \
    -var "porter_aws_role_name=${porter_aws_role_name}"

  popd >/dev/null
}

purge_state_path() {
  local bucket=$1
  local prefix=$2

  if ! $purge_state; then
    return
  fi

  echo "Removing Terraform state at gs://${bucket}/${prefix}..."
  gcloud storage rm --recursive "gs://${bucket}/${prefix}" --quiet || true
}

main() {
  resolve_args "$@"

  local bucket="porter-tfstate-${project_id}"
  local prefix="gcp-onboarding/${tenant_external_id}"

  run_terraform_destroy "${bucket}" "${prefix}"
  purge_state_path "${bucket}" "${prefix}"

  cat <<DONE

Porter access has been revoked from project ${project_id}.
The Workload Identity Pool, service account, and IAM bindings have been deleted.

DONE
}

main "$@"
