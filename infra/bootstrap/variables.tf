variable "project_id" {
  description = "GCP project of the lab, given by the instructor."
  type        = string
}

variable "region" {
  description = "Region of the state bucket."
  type        = string
  default     = "europe-west9"
}

variable "prefix" {
  description = "Group prefix used in every resource name, e.g. g3-movenow."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}[a-z0-9]$", var.prefix))
    error_message = "prefix must be 3 to 21 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "labels" {
  description = "Labels put on every resource that supports them."
  type        = map(string)
  default = {
    project     = "movenow"
    group       = "g3"
    environment = "bootstrap"
    managed_by  = "terraform"
  }
}

variable "github_repository" {
  description = "Repository allowed to use the CI identities, as owner/name with GitHub's exact casing."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "deploy_branch" {
  description = "Trusted branch whose workflows may plan with the plan identity."
  type        = string
  default     = "main"
}

variable "deploy_environment" {
  description = "GitHub environment, protected by required reviewers, whose jobs may apply with the apply identity."
  type        = string
  default     = "lab"
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. null derives it from the project and the prefix."
  type        = string
  default     = null
}

variable "plan_retention_days" {
  description = "Days a saved plan stays in the bucket before it is deleted."
  type        = number
  default     = 3
}

variable "state_versions_kept" {
  description = "Previous versions of each state file kept in the bucket."
  type        = number
  default     = 10
}

variable "plan_roles" {
  description = "Project roles of the plan identity: read the resources and their IAM policies, nothing else."
  type        = list(string)
  default = [
    "roles/viewer",
    "roles/iam.securityReviewer",
  ]
}

variable "apply_roles" {
  description = "Project roles of the apply identity: create, change and delete the lab resources."
  type        = list(string)
  default = [
    "roles/browser",
    "roles/bigquery.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/pubsub.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}
