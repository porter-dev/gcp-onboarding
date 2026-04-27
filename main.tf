locals {
  # APIs required for federation itself plus the IAM/Service Usage admin
  # surface. Everything else (compute, container, artifact registry, etc.)
  # is enabled by Porter's backend after federation is verified, so the
  # customer's Cloud Shell apply stays small and fast.
  bootstrap_apis = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ]

  # Bootstrap roles only. These give porter-manager just enough authority
  # to enable the remaining APIs and grant itself the heavier roles
  # (compute.admin, container.admin, artifactregistry.admin, etc.) from
  # Porter's backend post-onboarding. Mirrors the AWS pattern where the
  # CloudFormation stack creates a single porter-access-manager role and
  # Porter's CCP creates everything else.
  bootstrap_roles = [
    "roles/serviceusage.serviceUsageAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
  ]

  # Per-Porter-project resource names so the same GCP project can be
  # linked to multiple Porter projects without collision. Pool ID and
  # SA ID are derived if the variables are left empty.
  pool_id            = var.pool_id != "" ? var.pool_id : "porter-pool-${var.porter_project_id}"
  service_account_id = var.service_account_id != "" ? var.service_account_id : "porter-manager-${var.porter_project_id}"

  resource_labels = merge(var.labels, {
    porter-project-id = var.porter_project_id
    porter-tenant-id  = var.tenant_external_id
  })
}

data "google_project" "target" {
  project_id = var.project_id
}

resource "google_project_service" "bootstrap" {
  for_each = toset(local.bootstrap_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "porter_manager" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Impersonated by Porter via Workload Identity Federation. Managed by porter-dev/gcp-onboarding for Porter project ${var.porter_project_id}."

  depends_on = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "porter_manager_bootstrap" {
  for_each = toset(local.bootstrap_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.porter_manager.email}"
}

resource "google_iam_workload_identity_pool" "porter" {
  project                   = var.project_id
  workload_identity_pool_id = local.pool_id
  display_name              = "Porter (project ${var.porter_project_id})"
  description               = "Pool used by Porter project ${var.porter_project_id} to access this GCP project without long-lived service account keys."

  depends_on = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "porter_aws" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.porter.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "Porter (AWS)"
  description                        = "Trusts Porter's cluster control plane IAM role and pins access to this tenant by external ID."

  aws {
    account_id = var.porter_aws_account_id
  }

  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_account" = "assertion.account"
  }

  attribute_condition = join(" && ", [
    "assertion.account == '${var.porter_aws_account_id}'",
    "assertion.arn.startsWith('arn:aws:sts::${var.porter_aws_account_id}:assumed-role/${var.porter_aws_role_name}/')",
    "assertion.arn.endsWith('/porter-tenant-${var.tenant_external_id}')",
  ])
}

resource "google_service_account_iam_member" "porter_impersonation" {
  service_account_id = google_service_account.porter_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.porter.name}/attribute.aws_account/${var.porter_aws_account_id}"
}
