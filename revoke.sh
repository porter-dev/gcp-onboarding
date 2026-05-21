#!/usr/bin/env bash
#
# Removes Porter's access from the current GCP project. Destroys the
# service account, Workload Identity Pool, and the API enablement records
# owned by this deployment's Terraform state.
#
# Mirrors bootstrap.sh: all per-tenant configuration is fetched at
# runtime from Porter's API using three env vars the Porter dashboard's
# Revoke button pre-sets in your Cloud Shell session:
#
#   PORTER_API_URL              Base URL of the Porter API
#   PORTER_CLOUD_ACCOUNT_ID     UUID of the cloud_account row
#   PORTER_VERIFICATION_TOKEN   Single-use bearer token, validated by
#                               hash on the Porter side
#
# The state bucket itself is left in place so re-onboarding works without
# extra IAM. Pass --purge-state to also delete the state path.
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
    echo "  copy the setup command from the Porter dashboard's Revoke screen and paste it." >&2
    exit 1
  fi
}

parse_args() {
  purge_state=false
  for arg in "$@"; do
    case "$arg" in
      --purge-state) purge_state=true ;;
      *)
        echo "error: unknown argument '$arg'" >&2
        echo "usage: $0 [--purge-state]" >&2
        exit 1
        ;;
    esac
  done
}

fetch_details() {
  local url="${PORTER_API_URL%/}/api/v2/clouds/gcp/${PORTER_CLOUD_ACCOUNT_ID}/details"
  local payload
  payload=$(printf '{"verification_token":"%s"}' "${PORTER_VERIFICATION_TOKEN}")

  local response
  response=$(curl -sSf -X POST -H 'Content-Type: application/json' -d "${payload}" "${url}")

  porter_project_id=$(jq -r '.porter_project_id' <<<"${response}")
  gcp_project_id=$(jq -r '.gcp_project_id' <<<"${response}")
  tenant_external_id=$(jq -r '.tenant_external_id' <<<"${response}")
  porter_aws_account_id=$(jq -r '.porter_aws_account_id' <<<"${response}")
  porter_aws_role_name=$(jq -r '.porter_aws_role_name' <<<"${response}")

  if [[ -z $porter_project_id || $porter_project_id == null ||
        -z $gcp_project_id || $gcp_project_id == null ||
        -z $tenant_external_id || $tenant_external_id == null ||
        -z $porter_aws_account_id || $porter_aws_account_id == null ||
        -z $porter_aws_role_name || $porter_aws_role_name == null ]]; then
    echo "error: Porter /details response missing required fields" >&2
    echo "  raw response: ${response}" >&2
    exit 3
  fi

  cloud_account_id_lc=$(printf '%s' "${PORTER_CLOUD_ACCOUNT_ID}" | tr '[:upper:]' '[:lower:]')
  resource_suffix="${cloud_account_id_lc:0:4}"
}

run_terraform_destroy() {
  local bucket=$1
  local prefix=$2

  pushd "${script_dir}" >/dev/null

  "${TF_BIN:-terraform}" init \
    -input=false \
    -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${prefix}"

  "${TF_BIN:-terraform}" destroy \
    -input=false \
    -auto-approve \
    -var "project_id=${gcp_project_id}" \
    -var "tenant_external_id=${tenant_external_id}" \
    -var "porter_project_id=${porter_project_id}" \
    -var "cloud_account_id=${cloud_account_id_lc}" \
    -var "resource_suffix=${resource_suffix}" \
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
  parse_args "$@"

  require_env PORTER_API_URL
  require_env PORTER_CLOUD_ACCOUNT_ID
  require_env PORTER_VERIFICATION_TOKEN

  require_tool gcloud
  require_tool "${TF_BIN:-terraform}"
  require_tool curl
  require_tool jq

  fetch_details

  local bucket="porter-tfstate-${gcp_project_id}"
  local prefix="gcp-onboarding/${cloud_account_id_lc}"

  run_terraform_destroy "${bucket}" "${prefix}"
  purge_state_path "${bucket}" "${prefix}"

  cat <<DONE

Porter access has been revoked from project ${gcp_project_id}.
The Workload Identity Pool, service account, and IAM bindings have been deleted.

DONE
}

main "$@"
