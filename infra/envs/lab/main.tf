locals {
  services = [
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

module "messaging" {
  source = "../../modules/messaging"

  project_id                  = var.project_id
  prefix                      = var.prefix
  allowed_persistence_regions = [var.region]
  message_retention_duration  = var.message_retention_duration
  max_delivery_attempts       = var.max_delivery_attempts
  bigquery_table              = var.bigquery_table
  producer_impersonators      = var.producer_impersonators

  depends_on = [google_project_service.this]
}
