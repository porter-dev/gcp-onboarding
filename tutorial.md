# Connect Google Cloud to Porter

<walkthrough-disable-features toc></walkthrough-disable-features>

This tutorial gives Porter access to your Google Cloud project using
**Workload Identity Federation** — no service account keys, no long-lived
credentials. Setup takes about 30 seconds.

## What gets installed

Click <walkthrough-editor-open-file filePath="main.tf">main.tf</walkthrough-editor-open-file> to inspect every resource
this tutorial creates in your project. The summary:

- **Five APIs** enabled: Cloud Resource Manager, IAM, IAM Credentials,
  Security Token Service, and Service Usage. These are the ones needed to
  federate. Porter enables the rest (Compute, Kubernetes Engine, Artifact
  Registry, Container Registry, Secret Manager) afterward, server-side.
- **Service account** `porter-manager@<project>.iam.gserviceaccount.com` with
  the bootstrap IAM roles needed to provision the rest of Porter's setup:
  `serviceUsageAdmin`, `projectIamAdmin`, and `serviceAccountAdmin`. Porter
  grants the heavier per-service roles itself afterward.
- **Workload Identity Pool** `porter-pool` with an AWS provider that trusts
  *only* Porter's cluster control plane role for *only your tenant*.
- **Impersonation grant** allowing the federated identity to act as the
  service account.

Every resource is labeled `managed-by=porter` so you can find them later via
GCP Asset Inventory.

## Step 1: Confirm the configuration

Porter has provided you with three values. They should already be set in your
shell as environment variables. Confirm they match what you expect:

<walkthrough-execute-cloud-shell-command>
echo "Project:            ${PORTER_PROJECT_ID:-<not set>}"
echo "Tenant ID:          ${PORTER_TENANT_EXTERNAL_ID:-<not set>}"
echo "Porter AWS account: ${PORTER_AWS_ACCOUNT_ID:-<not set>}"
</walkthrough-execute-cloud-shell-command>

If any of those are empty, return to the Porter dashboard and copy the setup
command from the **Connect Google Cloud** screen — it sets these for you.

## Step 2: Run the setup

This invokes Terraform inside Cloud Shell. State is stored in a small GCS
bucket in your project (`porter-tfstate-<project-id>`) so revocation later is
deterministic.

<walkthrough-execute-cloud-shell-command>
./bootstrap.sh "$PORTER_PROJECT_ID" "$PORTER_TENANT_EXTERNAL_ID" "$PORTER_AWS_ACCOUNT_ID" "${PORTER_AWS_ROLE_NAME:-porter-ccp}"
</walkthrough-execute-cloud-shell-command>

Terraform will print the plan and apply it. You'll see green checks for each
of the few resources it creates.

## Step 3: Return to Porter

The Porter dashboard has been polling for completion since you started. As
soon as the federation works, Porter takes over server-side: enables the
remaining APIs and grants the remaining IAM roles. The dashboard's progress
bar climbs to 100% and the cluster creation flow advances automatically.

If the dashboard does not advance within 30 seconds of Terraform completing:
click **Retry verification** in Porter, or see
[the troubleshooting section in the README](https://github.com/porter-dev/gcp-onboarding#troubleshooting).

## Revocation

To remove Porter's access later:

- In Porter: **Integrations → Google Cloud → Revoke**. This opens a Cloud
  Shell tutorial that runs `terraform destroy` against the same state.
- Or directly: delete the `porter-pool` Workload Identity Pool in
  **IAM & Admin → Workload Identity Federation**. That single action
  invalidates all federated tokens immediately.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

You can close this tab now. Porter is ready.
