terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

locals {
  export_subscription      = regex("^projects/[^/]+/subscriptions/([^/]+)$", var.subscription_ids.export)[0]
  dead_letter_subscription = regex("^projects/[^/]+/subscriptions/([^/]+)$", var.subscription_ids.dead_letter)[0]

  export_filter      = "resource.type = \"pubsub_subscription\" AND resource.label.subscription_id = \"${local.export_subscription}\""
  dead_letter_filter = "resource.type = \"pubsub_subscription\" AND resource.label.subscription_id = \"${local.dead_letter_subscription}\""
}

resource "google_monitoring_dashboard" "pipeline" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "MoveNow - Pub/Sub et BigQuery"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Messages en attente - export BigQuery"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND ${local.export_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MAX"
                  }
                }
              }
              plotType = "LINE"
            }]
          }
        },
        {
          title = "Age du plus ancien message (secondes)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND ${local.export_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MAX"
                  }
                }
              }
              plotType = "LINE"
            }]
          }
        },
        {
          title = "Etat de l'export BigQuery (par statut)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type = \"pubsub.googleapis.com/subscription/export_push_subscription_details\" AND ${local.export_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MAX"
                  }
                }
              }
              plotType = "LINE"
            }]
          }
        },
        {
          title = "Messages transferes en dead-letter"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type = \"pubsub.googleapis.com/subscription/dead_letter_message_count\" AND metric.label.response_code = \"success\" AND ${local.export_filter}"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_SUM"
                  }
                }
              }
              plotType = "LINE"
            }]
          }
        },
        {
          title = "Messages a inspecter en dead-letter"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND ${local.dead_letter_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MAX"
                  }
                }
              }
              plotType = "LINE"
            }]
          }
        }
      ]
    }
  })
}

resource "google_monitoring_alert_policy" "backlog" {
  project               = var.project_id
  display_name          = "MoveNow - backlog export BigQuery"
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Messages en attente"
    condition_threshold {
      filter          = "metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND ${local.export_filter}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.backlog_threshold
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "delay" {
  project               = var.project_id
  display_name          = "MoveNow - retard export BigQuery"
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Age du plus ancien message"
    condition_threshold {
      filter          = "metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND ${local.export_filter}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.oldest_message_age_threshold_seconds
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "export_error" {
  project               = var.project_id
  display_name          = "MoveNow - erreur export BigQuery"
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Etat d'export non actif"
    condition_threshold {
      filter          = "metric.type = \"pubsub.googleapis.com/subscription/export_push_subscription_details\" AND metric.label.subscription_state != \"ACTIVE\" AND ${local.export_filter}"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "dead_letter" {
  project               = var.project_id
  display_name          = "MoveNow - messages en dead-letter"
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Transferts vers la dead-letter sur 5 minutes"
    condition_threshold {
      filter          = "metric.type = \"pubsub.googleapis.com/subscription/dead_letter_message_count\" AND metric.label.response_code = \"success\" AND ${local.export_filter}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.dead_letter_threshold
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
}
