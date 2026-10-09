locals {
  services = [
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]

  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_id}-${var.prefix}-tfstate")

  github_subject  = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_repository}"
  plan_principal  = "${local.github_subject}:ref:refs/heads/${var.deploy_branch}"
  apply_principal = "${local.github_subject}:environment:${var.deploy_environment}"
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

resource "google_storage_bucket" "state" {
  project                     = var.project_id
  name                        = local.state_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.state_versions_kept
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = var.plan_retention_days
      matches_prefix = ["plans/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    ignore_changes = [encryption]
  }

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.prefix}-github"
  display_name              = "GitHub Actions"
  description               = "CI of ${var.github_repository}"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }
  attribute_condition = join(" && ", [
    "assertion.repository_id == \"${var.github_repository_id}\"",
    "assertion.repository_owner_id == \"${var.github_repository_owner_id}\"",
    "assertion.ref == \"refs/heads/${var.deploy_branch}\"",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = "${var.prefix}-ci-plan"
  display_name = "CI plan"
  description  = "Runs terraform plan from ${var.github_repository} on ${var.deploy_branch}. Read only."
}

resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = "${var.prefix}-ci-apply"
  display_name = "CI apply"
  description  = "Applies reviewed plans from the ${var.deploy_environment} environment of ${var.github_repository}."
}

resource "google_service_account" "producer" {
  project      = var.project_id
  account_id   = "${var.prefix}-producer"
  display_name = "MoveNow producer"
  description  = "Publishes fake vehicle positions to the positions topic, nothing else."
}

resource "google_service_account_iam_member" "producer_impersonators" {
  for_each = toset(var.producer_impersonators)

  service_account_id = google_service_account.producer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_service_account_iam_member" "plan_workload_identity" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.plan_principal
}

resource "google_service_account_iam_member" "apply_workload_identity" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.apply_principal
}

resource "google_project_iam_member" "plan" {
  for_each = toset(var.plan_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.plan.member
}

resource "google_project_iam_member" "apply" {
  for_each = toset(var.apply_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.apply.member
}

resource "google_storage_bucket_iam_member" "state_plan_read" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.plan.member
}

resource "google_storage_bucket_iam_member" "state_plan_save_plans" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectCreator"
  member = google_service_account.plan.member

  condition {
    title       = "saved-plans-only"
    description = "Create new objects under plans/ only. Without delete, existing objects cannot be overwritten."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.state.name}/objects/plans/\")"
  }
}

resource "google_storage_bucket_iam_member" "state_apply_read" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.apply.member
}

resource "google_storage_bucket_iam_member" "state_apply_write" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.apply.member

  condition {
    title       = "lab-state-and-plans-only"
    description = "Write the lab state and the saved plans, never the bootstrap state."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.state.name}/objects/lab/\") || resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.state.name}/objects/plans/\")"
  }
}
