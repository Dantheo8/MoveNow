output "topic_name" {
  description = "Topic to pass to the producer with --topic."
  value       = module.messaging.topic_name
}

output "subscription_id" {
  description = "BigQuery subscription, watched by the backlog and oldest unacked message age alerts."
  value       = module.delivery.export_subscription_id
}

output "bigquery_table" {
  description = "Table holding the position history, project.dataset.table."
  value       = module.analytics.table_full_id
}

output "dead_letter_subscription_name" {
  description = "Inspection subscription of the dead-letter topic."
  value       = module.messaging.dead_letter_subscription_name
}

output "producer_service_account_email" {
  description = "Identity the producer runs as."
  value       = module.messaging.producer_service_account_email
}
