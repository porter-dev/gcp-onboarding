<!-- markdownlint-disable MD033 -- Cloud Shell walkthrough directives are HTML elements -->

# Connect Google Cloud to Porter

<walkthrough-disable-features toc></walkthrough-disable-features>

This tutorial gives Porter access to your Google Cloud project using
**Workload Identity Federation** — no service account keys, no long-lived
credentials. Setup takes about 30 seconds.

## Before you start

This Cloud Shell session was launched by the Porter dashboard. The setup
command the dashboard pasted into your shell exported three environment
variables that bind this run to your specific Porter integration:

- `PORTER_API_URL` — Porter's API endpoint.
- `PORTER_CLOUD_ACCOUNT_ID` — UUID of the cloud account row this
  integration creates in Porter.
- `PORTER_VERIFICATION_TOKEN` — a single-use bearer token Porter
  generated for this integration. The bootstrap script proves to Porter
  that the federation was set up by you, in this Cloud Shell session, and
  not by an attacker who guessed your IDs.

If you closed and reopened Cloud Shell, or arrived here without going
through the Porter dashboard, go back to **Porter → Integrations → Connect
Google Cloud** and copy the setup command from the **Connect Google
Cloud** screen. It exports the three variables above for you.

## What gets installed

Click <walkthrough-editor-open-file filePath="main.tf">main.tf</walkthrough-editor-open-file> to inspect every resource
this tutorial creates in your project. The summary:

- **Five APIs** enabled: Cloud Resource Manager, IAM, IAM Credentials,
  Security Token Service, and Service Usage. These are the ones needed
  to federate. Porter enables the rest (Compute, Kubernetes Engine,
  Artifact Registry, Container Registry, Secret Manager) afterward,
  server-side.
- **Service account** `porter-manager-<project>-<suffix>` with the
  bootstrap IAM roles needed to provision the rest of Porter's setup:
  `serviceUsageAdmin`, `projectIamAdmin`, and `serviceAccountAdmin`.
  Porter grants the heavier per-service roles itself afterward.
- **Workload Identity Pool** `porter-pool-<project>-<suffix>` with an AWS
  provider that trusts *only* Porter's cluster control plane role for
  *only your tenant*.
- **Impersonation grant** allowing the federated identity to act as the
  service account.

Resource names are stable per Porter cloud-account ID, so re-running this
script after a partial failure resumes from existing Terraform state
instead of creating parallel resources.

## Step 1: Run the setup

This invokes Terraform inside Cloud Shell. State is stored in a small GCS
bucket in your project (`porter-tfstate-<project>`) so revocation later is
deterministic.

<walkthrough-execute-cloud-shell-command>
./bootstrap.sh
</walkthrough-execute-cloud-shell-command>

The script fetches the per-integration parameters from Porter using your
verification token, runs `terraform apply`, and posts the resulting
service account email and Workload Identity provider name back to Porter
to consume the token.

You'll see green checks for each of the few resources Terraform creates.
If the script fails partway through, just re-run it — the state is
persisted, naming is stable, and the apply picks up where it left off.

## Step 2: Return to Porter

The Porter dashboard has been polling for federation since you started.
The status banner in the **Verify connection** step will update on its
own — first to "Provisioning WIF permissions" while Porter enables the
remaining APIs server-side and grants the heavier IAM roles, then to
"Cloud account is connected" once federation is confirmed. The dialog
closes automatically a moment later.

If the dashboard's status doesn't change within ~30 seconds of the
bootstrap script printing "Bootstrap complete.", just re-run the script
— it's idempotent and resumes from existing terraform state. See
[troubleshooting in the README](https://github.com/porter-dev/gcp-onboarding#troubleshooting)
if the re-run still doesn't move things along.

## Revoking later

There is no in-dashboard revoke action today. To disconnect Porter
later, delete the `porter-pool-*` Workload Identity Pool in **IAM & Admin
→ Workload Identity Federation** (this invalidates all federated tokens
immediately) and then delete the cloud account in Porter under
**Integrations → Cloud accounts**. Full instructions are in
[the README's *Revoking access* section](https://github.com/porter-dev/gcp-onboarding#revoking-access).

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

You can close this tab now. Porter is ready.
