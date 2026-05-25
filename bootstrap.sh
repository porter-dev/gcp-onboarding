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
#   PORTER_CLOUD_ACCOUNT_ID     UUID of the cloud_account row
#   PORTER_VERIFICATION_TOKEN   Single-use bearer token, validated by
#                               hash, consumed at the bootstrap callback
#
# Required IAM permissions on the GCP project (granted to the user
# running this script, NOT to porter-manager — porter-manager doesn't
# exist yet at this point):
#
#   - storage.buckets.create               creates the Terraform state bucket
#   - storage.objects.create               writes Terraform state objects + lockfile
#   - storage.objects.delete               releases the lockfile, manages state versions
#   - serviceusage.services.enable         enables the bootstrap APIs
#   - iam.serviceAccounts.create           creates the porter-manager-* service account
#   - iam.workloadIdentityPools.create     creates the federation pool and provider
#   - resourcemanager.projects.setIamPolicy   grants bootstrap roles to porter-manager-*
#
# roles/owner covers all of these. Otherwise, the project owner can
# grant them à la carte, or grant this convenience set which collectively
# covers the list:
#
#   roles/storage.admin
#   roles/serviceusage.serviceUsageAdmin
#   roles/iam.serviceAccountAdmin
#   roles/iam.workloadIdentityPoolAdmin
#   roles/resourcemanager.projectIamAdmin
#
set -euo pipefail

readonly script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# err_log captures stderr from every command in this script. on_failure
# greps it for the specific GCP permission that was denied (when one was)
# so the customer sees the exact missing permission, not just a generic
# "ask for owner" message.
readonly err_log=$(mktemp -t porter-bootstrap-err.XXXXXX)
trap 'rm -f "${err_log}"' EXIT
exec 2> >(tee -a "${err_log}" >&2)

print_required_permissions() {
  cat >&2 <<'MSG'
The account running this script needs these IAM permissions on the project:

  - storage.buckets.create               (creates the Terraform state bucket)
  - storage.objects.create               (writes Terraform state objects + lockfile)
  - storage.objects.delete               (releases the lockfile, manages state versions)
  - serviceusage.services.enable         (enables the bootstrap APIs)
  - iam.serviceAccounts.create           (creates the porter-manager-* service account)
  - iam.workloadIdentityPools.create     (creates the federation pool and provider)
  - resourcemanager.projects.setIamPolicy (grants bootstrap roles to porter-manager-*)

roles/owner covers all of these. Otherwise, the project owner can grant
them à la carte, or grant this convenience set which collectively covers
the list:

  roles/storage.admin
  roles/serviceusage.serviceUsageAdmin
  roles/iam.serviceAccountAdmin
  roles/iam.workloadIdentityPoolAdmin
  roles/resourcemanager.projectIamAdmin

MSG
}

on_failure() {
  local exit_code=$?

  cat >&2 <<MSG

================================================================
Bootstrap failed (exit ${exit_code}).
================================================================

MSG

  # Best-effort: extract the specific permission GCP rejected. GCP uses two
  # phrasings: "Permission 'xxx.yyy.zzz' denied" (most APIs) and "Required
  # 'xxx.yyy.zzz' permission" (Compute and a few others). Grep both.
  if [[ -f ${err_log} ]]; then
    local denied
    denied=$(grep -oE "Permission '[a-zA-Z0-9._-]+' denied|Required '[a-zA-Z0-9._-]+' permission" "${err_log}" | head -1 || true)
    if [[ -n ${denied} ]]; then
      cat >&2 <<MSG
GCP reported: ${denied}

The account you are running this script as is missing that permission on
the project. Ask a project owner to grant it (or grant a role that includes
it — see the full list below).

MSG
    fi
  fi

  print_required_permissions

  cat >&2 <<'MSG'
Bootstrap is idempotent: once permissions are fixed, re-run this script
and it will resume from existing state.

MSG

  exit "${exit_code}"
}

# ERR trap is installed inside main(), AFTER require_env/require_tool, so a
# missing env var or tool surfaces its own targeted message instead of being
# misdiagnosed as an IAM permission problem.

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

  # Derive the resource suffix from PORTER_CLOUD_ACCOUNT_ID, not from
  # tenant_external_id. tenant_external_id rotates per integration; the
  # cloud_account UUID is stable across retries of the same migration —
  # so the pool/SA names stay stable and a re-run of bootstrap.sh after
  # a partial failure reuses the same terraform state instead of leaving
  # orphan resources behind.
  cloud_account_id_lc=$(printf '%s' "${PORTER_CLOUD_ACCOUNT_ID}" | tr '[:upper:]' '[:lower:]')
  resource_suffix="${cloud_account_id_lc:0:4}"
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

  "${TF_BIN:-terraform}" init \
    -input=false \
    -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${prefix}"

  "${TF_BIN:-terraform}" apply \
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

notify_porter() {
  local project_number
  project_number=$(gcloud projects describe "${gcp_project_id}" --format='value(projectNumber)')
  if [[ -z $project_number ]]; then
    echo "error: failed to look up project number for ${gcp_project_id}" >&2
    exit 4
  fi

  pushd "${script_dir}" >/dev/null
  local sa_email wif_provider
  sa_email=$("${TF_BIN:-terraform}" output -raw service_account_email)
  wif_provider=$("${TF_BIN:-terraform}" output -raw workload_identity_provider)
  popd >/dev/null

  if [[ -z $sa_email || -z $wif_provider ]]; then
    echo "error: terraform outputs missing service_account_email or workload_identity_provider" >&2
    exit 5
  fi

  local payload
  payload=$(jq -nc \
    --arg token "${PORTER_VERIFICATION_TOKEN}" \
    --arg pn "${project_number}" \
    --arg email "${sa_email}" \
    --arg provider "${wif_provider}" \
    '{verification_token:$token, gcp_project_number:$pn, gcp_service_account_email:$email, workload_identity_provider:$provider}')

  local url="${PORTER_API_URL%/}/api/v2/clouds/gcp/${PORTER_CLOUD_ACCOUNT_ID}/bootstrap"
  echo "Notifying Porter at ${url}..."

  # Capture body + status code separately so we can treat a previously-
  # consumed verification token as success. That makes the whole script
  # genuinely idempotent: a re-run after the dashboard already accepted
  # the callback (e.g., the customer didn't notice the first run finished
  # cleanly) is a no-op rather than a confusing curl failure.
  local response_file
  response_file=$(mktemp)
  local status
  status=$(curl -sS -o "${response_file}" -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "${payload}" "${url}" || echo 000)

  if [[ $status == "200" || $status == "204" ]]; then
    rm -f "${response_file}"
    return
  fi

  local body
  body=$(cat "${response_file}")
  rm -f "${response_file}"

  if grep -qiE "already[ _-]?consumed" <<<"${body}"; then
    echo "Porter already accepted this bootstrap callback. Treating as success."
    return
  fi

  echo "error: bootstrap callback failed (HTTP ${status})" >&2
  echo "  body: ${body}" >&2
  exit 6
}

print_done() {
  cat <<DONE

================================================================
Bootstrap complete.

Porter has been notified. The dashboard is polling for federation
and will update on its own — it shows a status line like
"Provisioning WIF permissions (NN%)..." while Porter enables the
remaining APIs server-side and grants the heavier IAM roles to
porter-manager. When the cloud account is marked connected, the
dialog closes automatically.

If the dashboard doesn't update within ~30 seconds, re-run this
script — it's idempotent and resumes from the existing terraform
state in GCS.

You can close this tab now.
================================================================

DONE
}

main() {
  require_env PORTER_API_URL
  require_env PORTER_CLOUD_ACCOUNT_ID
  require_env PORTER_VERIFICATION_TOKEN

  require_tool gcloud
  require_tool "${TF_BIN:-terraform}"
  require_tool curl
  require_tool jq

  # Install ERR trap only after the prereq checks pass — anything that
  # fails from here on is an actual GCP-side problem that benefits from
  # the IAM-permission diagnostic.
  trap on_failure ERR

  fetch_details

  local bucket="porter-tfstate-${gcp_project_id}"
  # State prefix is keyed on cloud_account_id (not tenant_external_id) so a
  # retry of the same migration finds the same state and resumes idempotently.
  local prefix="gcp-onboarding/${cloud_account_id_lc}"

  ensure_state_bucket "${bucket}"
  run_terraform "${bucket}" "${prefix}"
  notify_porter
  print_done
}

main "$@"
