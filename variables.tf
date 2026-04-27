variable "project_id" {
  description = "The GCP project ID where Porter will be granted access."
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase, digits, hyphens)."
  }
}

variable "tenant_external_id" {
  description = "Per-tenant external ID issued by Porter. Embedded in the Workload Identity attribute condition so only Porter sessions for this specific tenant can impersonate the service account."
  type        = string

  validation {
    condition     = length(var.tenant_external_id) >= 8
    error_message = "tenant_external_id must be at least 8 characters."
  }
}

variable "porter_aws_account_id" {
  description = "The 12-digit AWS account ID Porter's cluster control plane runs in. The Workload Identity provider will only trust assumed-role sessions originating from this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.porter_aws_account_id))
    error_message = "porter_aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "porter_aws_role_name" {
  description = "Name of the IAM role Porter's cluster control plane assumes. The provider validates the session ARN's role segment against this value."
  type        = string
  default     = "porter-ccp"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.porter_aws_role_name))
    error_message = "porter_aws_role_name must be a valid IAM role name."
  }
}

variable "pool_id" {
  description = "Workload Identity Pool ID."
  type        = string
  default     = "porter-pool"
}

variable "provider_id" {
  description = "Workload Identity Pool Provider ID."
  type        = string
  default     = "porter-aws"
}

variable "service_account_id" {
  description = "Service account ID Porter will impersonate."
  type        = string
  default     = "porter-manager"
}

variable "service_account_display_name" {
  description = "Display name shown in the GCP console for the Porter service account."
  type        = string
  default     = "Porter Manager"
}

variable "labels" {
  description = "Labels applied to all label-able resources for asset-inventory discovery."
  type        = map(string)
  default = {
    managed-by = "porter"
  }
}
