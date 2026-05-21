# Revoke Porter's access to Google Cloud

<walkthrough-disable-features toc></walkthrough-disable-features>

This tutorial removes everything `porter-dev/gcp-onboarding` previously
installed in your project. After completion, Porter can no longer access
this Google Cloud project.

## Before you start

This Cloud Shell session was launched by the Porter dashboard's **Revoke**
button. The setup command the dashboard pasted into your shell exported
three environment variables that bind this run to your specific Porter
integration:

- `PORTER_API_URL`
- `PORTER_CLOUD_ACCOUNT_ID`
- `PORTER_VERIFICATION_TOKEN`

If you closed and reopened Cloud Shell, go back to **Porter → Integrations
→ Google Cloud → Revoke** and copy the setup command again.

## What gets removed

- The `porter-manager-*` service account and all its IAM role bindings.
- The `porter-pool-*` Workload Identity Pool and its AWS provider.
- The impersonation grant that let Porter's federated identity act as
  the service account.

The API enablements remain (deleting them might break other workloads in
your project). The Terraform state bucket also remains so future
re-onboarding is faster — pass `--purge-state` if you want the state path
gone too.

## Step 1: Run the destroy

<walkthrough-execute-cloud-shell-command>
./revoke.sh
</walkthrough-execute-cloud-shell-command>

Terraform will list every resource it intends to delete and then remove
them. Federated tokens issued before this point continue to work for up
to their remaining lifetime (max one hour); after that all access is
gone.

## Step 2: Return to Porter

The Porter dashboard polls for revocation in the same way it polled
during onboarding. Once the resources are gone, the integration
disappears from **Integrations → Google Cloud**.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Porter has been disconnected.
