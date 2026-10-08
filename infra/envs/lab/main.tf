locals {
  services = [
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "monitoring.googleapis.com",
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
  producer_impersonators      = var.producer_impersonators

  depends_on = [google_project_service.this]
}

module "analytics" {
  source = "../../modules/analytics"

  project_id          = var.project_id
  location            = var.region
  dataset_id          = replace(var.prefix, "-", "_")
  table_id            = "positions"
  schema              = file("${path.module}/../../schemas/positions.json")
  retention_days      = var.retention_days
  deletion_protection = var.table_deletion_protection
  labels              = var.labels

  depends_on = [google_project_service.this]
}

module "delivery" {
  source = "../../modules/delivery"

  project_id                 = var.project_id
  subscription_name          = "${var.prefix}-positions-bq"
  topic_id                   = module.messaging.topic_id
  dead_letter_topic_id       = module.messaging.dead_letter_topic_id
  service_agent              = module.messaging.pubsub_service_agent_email
  table_id                   = module.analytics.table_full_id
  message_retention_duration = var.message_retention_duration
  max_delivery_attempts      = var.max_delivery_attempts
}

module "observability" {
  source = "../../modules/observability"

  project_id = var.project_id
  subscription_ids = {
    export      = module.delivery.export_subscription_id
    dead_letter = module.messaging.dead_letter_subscription_id
  }
  notification_channels = var.notification_channels

  depends_on = [google_project_service.this]
}
