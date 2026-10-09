output "topic_id" {
  description = "Full id of the positions topic, projects/<project>/topics/<name>."
  value       = google_pubsub_topic.positions.id
}

output "topic_name" {
  description = "Short name of the positions topic, passed to the producer with --topic."
  value       = google_pubsub_topic.positions.name
}

output "dead_letter_topic_id" {
  description = "Full id of the dead-letter topic, used by the delivery subscription's dead-letter policy."
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
  description = "Identity the producer runs as, allowed to publish to the positions topic."
  value       = var.producer_service_account_email
}

output "pubsub_service_agent_email" {
  description = "Email of the Pub/Sub service agent, which writes to BigQuery and dead-letters messages. Available once the topics exist, so that Google has provisioned the agent before anyone grants it a role."
  value       = local.pubsub_service_agent_email
  depends_on  = [google_pubsub_topic.positions, google_pubsub_topic.dead_letter]
}
