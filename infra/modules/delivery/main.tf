terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

locals {
  dead_letter_parts = regex("^projects/([^/]+)/topics/([^/]+)$", var.dead_letter_topic_id)
  table_parts       = regex("^([^.]+)\\.([^.]+)\\.([^.]+)$", var.table_id)
  writer_member     = "serviceAccount:${var.service_agent}"
}

resource "google_bigquery_table_iam_member" "writer" {
  project    = local.table_parts[0]
  dataset_id = local.table_parts[1]
  table_id   = local.table_parts[2]
  role       = "roles/bigquery.dataEditor"
  member     = local.writer_member
}

resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  project = local.dead_letter_parts[0]
  topic   = local.dead_letter_parts[1]
  role    = "roles/pubsub.publisher"
  member  = local.writer_member
}

resource "google_pubsub_subscription" "export" {
  project = var.project_id
  name    = var.subscription_name
  topic   = var.topic_id

  bigquery_config {
    table            = var.table_id
    use_table_schema = true
  }

  retry_policy {
    minimum_backoff = var.retry_minimum_backoff
    maximum_backoff = var.retry_maximum_backoff
  }

  dead_letter_policy {
    dead_letter_topic     = var.dead_letter_topic_id
    max_delivery_attempts = var.max_delivery_attempts
  }

  depends_on = [
    google_bigquery_table_iam_member.writer,
    google_pubsub_topic_iam_member.dead_letter_publisher,
  ]
}

resource "google_pubsub_subscription_iam_member" "dead_letter_acknowledger" {
  project      = var.project_id
  subscription = google_pubsub_subscription.export.name
  role         = "roles/pubsub.subscriber"
  member       = local.writer_member
}
