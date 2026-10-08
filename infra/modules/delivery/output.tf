output "writer_identity" {
  description = "Identité IAM du service agent qui écrit dans BigQuery et traite la dead-letter."
  value       = local.writer_member
}

output "export_subscription_id" {
  description = "Nom complet de la subscription de transfert vers BigQuery."
  value       = google_pubsub_subscription.export.id
}
