# Revoke Porter's access to Google Cloud

<walkthrough-disable-features toc></walkthrough-disable-features>

This tutorial removes everything `porter-dev/gcp-onboarding` previously
installed in your project. After completion, Porter can no longer access
this Google Cloud project.

## What gets removed

- The `porter-manager` service account and all its IAM role bindings.
- The `porter-pool` Workload Identity Pool and its AWS provider.
- The impersonation grant that let Porter's federated identity act as the
  service account.

The API enablements remain (deleting them might break other workloads in
your project). The Terraform state bucket also remains so future re-onboarding
is faster — pass `--purge-state` if you want it gone too.

## Step 1: Confirm the configuration

```bash
echo "Project:            ${PORTER_PROJECT_ID:-<not set>}"
echo "Tenant ID:          ${PORTER_TENANT_EXTERNAL_ID:-<not set>}"
echo "Porter AWS account: ${PORTER_AWS_ACCOUNT_ID:-<not set>}"
```

<walkthrough-execute-cloud-shell-command>
echo "Project:            ${PORTER_PROJECT_ID:-<not set>}"
echo "Tenant ID:          ${PORTER_TENANT_EXTERNAL_ID:-<not set>}"
echo "Porter AWS account: ${PORTER_AWS_ACCOUNT_ID:-<not set>}"
</walkthrough-execute-cloud-shell-command>

If any value is missing, return to Porter — the **Revoke** action sets these
in your shell.

## Step 2: Run the destroy

<walkthrough-execute-cloud-shell-command>
./revoke.sh "$PORTER_PROJECT_ID" "$PORTER_TENANT_EXTERNAL_ID" "$PORTER_AWS_ACCOUNT_ID" "${PORTER_AWS_ROLE_NAME:-porter-ccp}"
</walkthrough-execute-cloud-shell-command>

Terraform will list every resource it intends to delete and then remove
them. Federated tokens issued before this point continue to work for up to
their remaining lifetime (max one hour); after that all access is gone.

## Step 3: Return to Porter

The Porter dashboard polls for revocation in the same way it polled during
onboarding. Once the resources are gone, the integration disappears from
**Integrations → Google Cloud**.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Porter has been disconnected.
