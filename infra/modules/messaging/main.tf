data "google_project" "this" {
  project_id = var.project_id
}

locals {
  pubsub_service_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  bigquery_table_id = (
    var.bigquery_table == null ? null :
    "${var.bigquery_table.project}.${var.bigquery_table.dataset_id}.${var.bigquery_table.table_id}"
  )
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

resource "google_pubsub_subscription" "positions" {
  project                    = var.project_id
  name                       = "${var.prefix}-positions-bq"
  topic                      = google_pubsub_topic.positions.id
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = var.minimum_backoff
    maximum_backoff = var.maximum_backoff
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  dynamic "bigquery_config" {
    for_each = var.bigquery_table == null ? [] : [1]
    content {
      table               = local.bigquery_table_id
      use_table_schema    = true
      write_metadata      = var.bigquery_write_metadata
      drop_unknown_fields = var.bigquery_drop_unknown_fields
    }
  }

  depends_on = [google_bigquery_table_iam_member.pubsub_writer]
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

resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter.name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_service_agent
}

resource "google_pubsub_subscription_iam_member" "dead_letter_source_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.positions.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_agent
}

resource "google_bigquery_table_iam_member" "pubsub_writer" {
  count = var.bigquery_table == null ? 0 : 1

  project    = var.bigquery_table.project
  dataset_id = var.bigquery_table.dataset_id
  table_id   = var.bigquery_table.table_id
  role       = "roles/bigquery.dataEditor"
  member     = local.pubsub_service_agent

  depends_on = [google_pubsub_topic.positions]
}

resource "google_service_account" "producer" {
  project      = var.project_id
  account_id   = "${var.prefix}-producer"
  display_name = "MoveNow producer"
  description  = "Publishes fake vehicle positions to the positions topic, nothing else."
}

resource "google_pubsub_topic_iam_member" "producer_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.positions.name
  role    = "roles/pubsub.publisher"
  member  = google_service_account.producer.member
}

resource "google_service_account_iam_member" "producer_impersonators" {
  for_each = toset(var.producer_impersonators)

  service_account_id = google_service_account.producer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}
