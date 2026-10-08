output "topic_id" {
  description = "Full id of the positions topic, projects/<project>/topics/<name>."
  value       = google_pubsub_topic.positions.id
}

output "topic_name" {
  description = "Short name of the positions topic, passed to the producer with --topic."
  value       = google_pubsub_topic.positions.name
}

output "subscription_id" {
  description = "Full id of the main subscription."
  value       = google_pubsub_subscription.positions.id
}

output "subscription_name" {
  description = "Short name of the main subscription: the backlog and oldest unacked message age alerts watch it."
  value       = google_pubsub_subscription.positions.name
}

output "delivery_mode" {
  description = "bigquery when the main subscription writes to the table, pull otherwise."
  value       = var.bigquery_table == null ? "pull" : "bigquery"
}

output "dead_letter_topic_id" {
  description = "Full id of the dead-letter topic."
  value       = google_pubsub_topic.dead_letter.id
}

output "dead_letter_subscription_id" {
  description = "Full id of the inspection subscription on the dead-letter topic."
  value       = google_pubsub_subscription.dead_letter_inspection.id
}

output "dead_letter_subscription_name" {
  description = "Short name of the inspection subscription: the dead-letter alert watches it, the dashboard reads it."
  value       = google_pubsub_subscription.dead_letter_inspection.name
}

output "producer_service_account_email" {
  description = "Identity the producer runs as."
  value       = google_service_account.producer.email
}

output "pubsub_service_agent" {
  description = "IAM member of the Pub/Sub service agent, which dead-letters messages and writes to BigQuery."
  value       = local.pubsub_service_agent
}
