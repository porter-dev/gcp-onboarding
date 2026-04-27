# porter-dev/gcp-onboarding

Connects a Google Cloud project to [Porter](https://porter.run) using
**Workload Identity Federation** instead of long-lived service account keys.

This repository is the source for the Cloud Shell tutorial that opens when
you click **Connect Google Cloud** in the Porter dashboard. It's also safe
to clone and run by hand.

## What this installs

In the GCP project you supply, this Terraform module creates:

- **API enablements** for the ten services Porter needs: Compute, GKE,
  Cloud Resource Manager, Artifact Registry, Container Registry, Secret
  Manager, IAM, IAM Credentials, Service Usage, and STS.
- **A `porter-manager` service account** — the identity Porter impersonates.
  Has no key.
- **Project IAM role bindings** granting the service account the roles Porter
  needs to manage clusters, registries, and secrets. See `main.tf` for the
  full list.
- **A `porter-pool` Workload Identity Pool** — the federation surface that
  converts AWS credentials into GCP credentials.
- **An AWS provider on the pool** that trusts *only* Porter's cluster control
  plane IAM role, and *only* sessions tagged with the tenant external ID
  Porter generated for you.
- **An impersonation IAM binding** letting the federated principal act as
  `porter-manager`.

Every resource is labeled `managed-by=porter` and
`porter-tenant-id=<your-tenant-id>` so you can find them in Asset Inventory.

## Why no service account key

A downloaded JSON key is a forever-credential: if it leaks, the attacker has
your project until you remember to rotate. Workload Identity Federation
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

A leak of the Workload Identity provider name + service account email cannot
be turned into access without also compromising Porter's AWS infrastructure.

## Running the tutorial

The Porter dashboard generates a Cloud Shell deeplink that opens this repo
with the right environment variables set. You should not normally invoke
this repo directly.

If you want to anyway:

```bash
git clone https://github.com/porter-dev/gcp-onboarding
cd gcp-onboarding

./bootstrap.sh \
  <project-id> \
  <tenant-external-id> \
  <porter-aws-account-id> \
  [porter-aws-role-name]
```

The script:

1. Creates a GCS bucket `porter-tfstate-<project-id>` if it doesn't exist
   and uses it as the Terraform backend.
2. Runs `terraform init` and `terraform apply` against the module in this
   directory.
3. Prints the Workload Identity Provider name and service account email.

To revoke later:

```bash
./revoke.sh <project-id> <tenant-external-id> <porter-aws-account-id>
```

## Required permissions

The Google account running the tutorial needs, at minimum, the following
roles on the target project:

- `roles/serviceusage.serviceUsageAdmin` (to enable APIs)
- `roles/iam.serviceAccountAdmin` (to create the SA)
- `roles/resourcemanager.projectIamAdmin` (to grant project-level roles)
- `roles/iam.workloadIdentityPoolAdmin` (to create the pool and provider)
- `roles/storage.admin` (to create the state bucket — only needed on first run)

`roles/owner` covers all of these. Most customer-side Porter installers have
project owner already.

## Versioning

Releases are tagged `vX.Y.Z`. The Porter dashboard pins its Cloud Shell
deeplinks to specific tags. Breaking changes to inputs or outputs are gated
on a major-version bump and a coordinated dashboard release.

## Troubleshooting

**`Error: googleapi: Error 403: Permission ... denied on service ...`**
The Service Usage API or Cloud Resource Manager API is disabled at the
organization level. Re-run the script after an org admin enables them.

**`Error: ... is not authorized to perform: iam.serviceAccounts.actAs`**
The Google account you ran the tutorial as does not have project-IAM-admin
on the target project. See *Required permissions* above.

**Porter dashboard never advances**
Verify the outputs printed at the end of `bootstrap.sh` match what Porter
expects, then click **Retry verification** in the dashboard. If it still
fails, contact Porter support with the tenant external ID — that's enough
for them to find your integration.

## License

Apache 2.0.
