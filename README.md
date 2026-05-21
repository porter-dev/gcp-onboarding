# porter-dev/gcp-onboarding

Connects a Google Cloud project to [Porter](https://porter.run) using
**Workload Identity Federation** instead of long-lived service account keys.

This repository is the source for the Cloud Shell tutorial that opens when
you click **Connect Google Cloud** (or **Migrate to WIF**) in the Porter
dashboard. The code is open so you can review every IAM grant before
running it. The tutorial is meant to be launched from the dashboard — the
dashboard's setup command is what binds this script to your specific Porter
integration.

## What this installs

In the GCP project you supply, `main.tf` creates:

- **Five API enablements** required for federation itself: Service Usage,
  Cloud Resource Manager, IAM, IAM Credentials, and STS. The heavier APIs
  (Compute, GKE, Artifact Registry, Container Registry, Secret Manager)
  are enabled by Porter server-side after federation works, keeping the
  Cloud Shell apply small and fast.
- **A `porter-manager-<project>-<suffix>` service account** — the identity
  Porter impersonates. Has no key.
- **Bootstrap IAM bindings** on that SA: `serviceUsageAdmin`,
  `projectIamAdmin`, and `serviceAccountAdmin`. Just enough to enable the
  remaining APIs and grant the heavier roles itself, post-federation.
- **A `porter-pool-<project>-<suffix>` Workload Identity Pool** — the
  federation surface that converts AWS credentials into GCP credentials.
- **An AWS provider on the pool** that trusts *only* Porter's cluster
  control plane IAM role, and *only* sessions tagged with the tenant
  external ID Porter generated for your integration.
- **An impersonation IAM binding** letting the federated principal act as
  `porter-manager`.

## Stable resource identity

The `<suffix>` is the first 4 hex characters of your Porter `cloud_account`
UUID. That UUID is stable across retries of the same integration — so if a
mid-run failure leaves the apply half-completed, re-running `bootstrap.sh`
finds the same Terraform state in GCS and resumes from where it stopped,
rather than creating a parallel set of resources.

A fresh `cloud_account` (i.e., a from-scratch reconnection in the dashboard)
gets a fresh suffix, which avoids colliding with the 30-day soft-deleted
siblings of any prior teardown.

Every resource's `description` field is stamped with the full Porter
ownership tuple:

```
managed-by=porter
porter-project-id=<id>
porter-cloud-account-id=<uuid>
porter-tenant-id=<id>
```

GCP IAM resources (service accounts, workload identity pools, providers)
don't accept labels, so the `description` is the only field that
round-trips through `gcloud ... describe` for asset-inventory lookups.

## Why no service account key

A downloaded JSON key is a forever-credential: if it leaks, the attacker
has your project until you remember to rotate. Workload Identity Federation
issues short-lived (≤1 hour) tokens minted on demand from Porter's AWS
identity. There is no secret to rotate, store, or leak.

## Trust setup

The Workload Identity provider's attribute condition is the security
boundary. It validates three things on every federation request:

1. The AWS account ID matches Porter's published account ID.
2. The assumed-role ARN matches Porter's published role name (default
   `porter-ccp`).
3. The session name ends with `porter-tenant-<your-tenant-id>`. Porter
   generates this ID per integration; it is unique to this deployment.

A leak of the Workload Identity provider name + service account email
cannot be turned into access without also compromising Porter's AWS
infrastructure.

## Running it

You should not normally invoke this repo directly. The Porter dashboard
generates a Cloud Shell deeplink that:

1. Clones this repo into Cloud Shell.
2. Sets three environment variables (`PORTER_API_URL`,
   `PORTER_CLOUD_ACCOUNT_ID`, `PORTER_VERIFICATION_TOKEN`).
3. Opens `tutorial.md` in the Cloud Shell sidebar.

`bootstrap.sh` then:

1. Calls Porter's `/details` endpoint with your verification token to
   fetch the per-integration parameters (Porter project ID, GCP project
   ID, tenant external ID, Porter AWS account ID, role name).
2. Creates a GCS bucket `porter-tfstate-<gcp-project>` if needed and
   writes Terraform state under `gcp-onboarding/<cloud-account-id>`.
3. Runs `terraform apply` against the module in this directory.
4. POSTs the resulting service account email and Workload Identity
   provider name back to Porter's `/bootstrap` endpoint, consuming the
   verification token.

If you really want to run it by hand outside the dashboard, set the three
env vars first:

```bash
export PORTER_API_URL=https://api.porter.run
export PORTER_CLOUD_ACCOUNT_ID=<uuid-from-porter-dashboard>
export PORTER_VERIFICATION_TOKEN=<single-use-token-from-porter-dashboard>

./bootstrap.sh
```

See *Revoking access* below for how to disconnect later — it's a manual
procedure today, not a dashboard action.

## Required permissions

The Google account running the tutorial needs, at minimum, the following
roles on the target project:

- `roles/serviceusage.serviceUsageAdmin` (to enable APIs)
- `roles/iam.serviceAccountAdmin` (to create the SA)
- `roles/resourcemanager.projectIamAdmin` (to grant project-level roles)
- `roles/iam.workloadIdentityPoolAdmin` (to create the pool and provider)
- `roles/storage.admin` (to create the state bucket — only needed on
  first run)

`roles/owner` covers all of these. Most customer-side Porter installers
have project owner already.

## Revoking access

There is no in-dashboard revoke action today. To disconnect Porter, do
both of the following:

1. **GCP side: delete the resources.** The fastest, most decisive cut is
   to delete the `porter-pool-*` Workload Identity Pool in the GCP
   console under **IAM & Admin → Workload Identity Federation**. That
   single action invalidates all federated tokens immediately. You can
   also delete the `porter-manager-*` service account afterward to clean
   up. Federated tokens already issued continue to work until they
   expire (≤1 hour); deleting the pool prevents new ones.

   Or, if you cloned this repo and want a clean `terraform destroy`, run
   it with the values you used at onboarding (you'll need to know your
   GCP project ID, Porter project ID, cloud_account UUID, tenant
   external ID, and Porter's AWS account ID — the last is published in
   our docs):

   ```bash
   terraform init -backend-config="bucket=porter-tfstate-<gcp-project>" \
                  -backend-config="prefix=gcp-onboarding/<cloud-account-uuid>"
   terraform destroy \
     -var "project_id=<gcp-project>" \
     -var "porter_project_id=<porter-project>" \
     -var "cloud_account_id=<cloud-account-uuid>" \
     -var "resource_suffix=<first-4-hex-of-cloud-account-uuid>" \
     -var "tenant_external_id=<tenant-external-id>" \
     -var "porter_aws_account_id=<porter-aws-account-id>"
   ```

2. **Porter side: delete the cloud account row.** Removing the GCP
   resources stops Porter's federation but doesn't remove the
   integration from the dashboard. Delete the cloud account in
   **Integrations → Cloud accounts** to finish the cleanup.

## Versioning

Releases are tagged `vX.Y.Z`. The Porter dashboard pins its Cloud Shell
deeplinks to specific tags. Breaking changes to inputs or outputs are
gated on a major-version bump and a coordinated dashboard release.

## Troubleshooting

**`error: required env var PORTER_API_URL is not set`**
You launched the script outside the Porter dashboard's Cloud Shell flow,
or the dashboard's setup command did not run. Return to the Porter
dashboard and click **Connect Google Cloud** again — that re-opens Cloud
Shell with the env vars pre-set.

**`Error: googleapi: Error 403: Permission ... denied on service ...`**
The Service Usage API or Cloud Resource Manager API is disabled at the
organization level. Re-run the script after an org admin enables them.

**`Error: ... is not authorized to perform: iam.serviceAccounts.actAs`**
The Google account you ran the tutorial as does not have project-IAM-admin
on the target project. See *Required permissions* above.

**Porter dashboard never updates from "Waiting for bootstrap callback..."**
Verify the bootstrap script finished cleanly (look for "Bootstrap
complete."). If it did, re-run `./bootstrap.sh` — the script is
idempotent, so a second run is harmless and will re-post the bootstrap
callback to Porter. If the status still doesn't move, contact Porter
support with your tenant external ID — that is enough to find your
integration.

## License

Apache 2.0.
