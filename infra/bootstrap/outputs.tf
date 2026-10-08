output "state_bucket" {
  description = "Bucket holding the Terraform state of the lab and the saved plans."
  value       = google_storage_bucket.state.name
}

output "workload_identity_provider" {
  description = "Full name of the GitHub provider, for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account" {
  description = "Identity of the plan jobs."
  value       = google_service_account.plan.email
}

output "apply_service_account" {
  description = "Identity of the apply and destroy jobs."
  value       = google_service_account.apply.email
}

output "github_variables" {
  description = "Repository variables to create in GitHub (Settings, Secrets and variables, Actions, Variables)."
  value = {
    GCP_PROJECT_ID            = var.project_id
    GCP_REGION                = var.region
    TF_PREFIX                 = var.prefix
    TF_STATE_BUCKET           = google_storage_bucket.state.name
    GCP_WIF_PROVIDER          = google_iam_workload_identity_pool_provider.github.name
    GCP_PLAN_SERVICE_ACCOUNT  = google_service_account.plan.email
    GCP_APPLY_SERVICE_ACCOUNT = google_service_account.apply.email
  }
}
