output "dashboard_id" {
  description = "Identifiant du dashboard Cloud Monitoring."
  value       = google_monitoring_dashboard.pipeline.id
}

output "alert_policy_ids" {
  description = "Identifiants des politiques d'alerte creees."
  value = {
    backlog      = google_monitoring_alert_policy.backlog.id
    delay        = google_monitoring_alert_policy.delay.id
    export_error = google_monitoring_alert_policy.export_error.id
    dead_letter  = google_monitoring_alert_policy.dead_letter.id
  }
}
