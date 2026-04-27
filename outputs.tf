output "workload_identity_provider" {
  description = "Full resource name of the Workload Identity Pool provider. Paste this into Porter."
  value       = "projects/${data.google_project.target.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.porter.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.porter_aws.workload_identity_pool_provider_id}"
}

output "service_account_email" {
  description = "Service account Porter will impersonate. Paste this into Porter."
  value       = google_service_account.porter_manager.email
}

output "project_id" {
  description = "GCP project ID this deployment configured."
  value       = var.project_id
}

output "tenant_external_id" {
  description = "Porter tenant external ID this deployment is bound to."
  value       = var.tenant_external_id
}
