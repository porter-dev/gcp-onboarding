# Connect Google Cloud to Porter

<walkthrough-disable-features toc></walkthrough-disable-features>

This tutorial gives Porter access to your Google Cloud project using
**Workload Identity Federation** — no service account keys, no long-lived
credentials. Setup takes about 90 seconds.

## What gets installed

Click <walkthrough-editor-open-file filePath="main.tf">main.tf</walkthrough-editor-open-file> to inspect every resource
this tutorial creates in your project. The summary:

- **Required APIs** enabled: Compute, Kubernetes Engine, Cloud Resource Manager,
  Artifact Registry, Container Registry, Secret Manager, IAM, IAM Credentials,
  Service Usage, and Security Token Service.
- **Service account** `porter-manager@<project>.iam.gserviceaccount.com` with
  the IAM roles Porter needs to manage clusters, registries, and secrets.
- **Workload Identity Pool** `porter-pool` with an AWS provider that trusts
  *only* Porter's cluster control plane role for *only your tenant*.
- **Impersonation grant** allowing the federated identity to act as the
  service account.

Every resource is labeled `managed-by=porter` so you can find them later via
GCP Asset Inventory.

## Step 1: Confirm the configuration

Porter has provided you with three values. They should already be set in your
shell as environment variables. Confirm they match what you expect:

```bash
echo "Project:           ${PORTER_PROJECT_ID:-<not set>}"
echo "Tenant ID:         ${PORTER_TENANT_EXTERNAL_ID:-<not set>}"
echo "Porter AWS account: ${PORTER_AWS_ACCOUNT_ID:-<not set>}"
```

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

Terraform will print the plan, apply it, and show two output values at the
end: the **Workload Identity Provider** resource name and the **Service Account
Email**. Both will already have been registered with the Porter dashboard
in your other tab — you do not need to copy them by hand.

## Step 3: Return to Porter

The Porter dashboard has been polling for completion since you started. As
soon as Terraform finishes, the **Connect Google Cloud** step turns green and
the cluster creation flow advances.

If the dashboard does not advance within 30 seconds of Terraform completing:

1. Verify the outputs above are non-empty.
2. Click **Retry verification** in Porter.
3. If verification still fails, see
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
