data "google_project" "this" {
  project_id = var.project_id
}

locals {
  pubsub_service_agent_email = "service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "positions" {
  project                    = var.project_id
  name                       = "${var.prefix}-positions"
  message_retention_duration = var.topic_message_retention_duration

  dynamic "message_storage_policy" {
    for_each = length(var.allowed_persistence_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = var.allowed_persistence_regions
    }
  }
}

resource "google_pubsub_topic" "dead_letter" {
  project = var.project_id
  name    = "${var.prefix}-positions-dead-letter"

  dynamic "message_storage_policy" {
    for_each = length(var.allowed_persistence_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = var.allowed_persistence_regions
    }
  }
}

resource "google_pubsub_subscription" "dead_letter_inspection" {
  project                    = var.project_id
  name                       = "${var.prefix}-positions-dead-letter-inspection"
  topic                      = google_pubsub_topic.dead_letter.id
  ack_deadline_seconds       = 60
  message_retention_duration = var.dead_letter_message_retention_duration

  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_topic_iam_member" "producer_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.positions.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.producer_service_account_email}"
}
