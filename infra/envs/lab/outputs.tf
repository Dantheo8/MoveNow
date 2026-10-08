output "topic_name" {
  description = "Topic to pass to the producer with --topic."
  value       = module.messaging.topic_name
}

output "subscription_name" {
  description = "Main subscription, watched by the backlog and oldest unacked message age alerts."
  value       = module.messaging.subscription_name
}

output "delivery_mode" {
  description = "bigquery once bigquery_table is set, pull before that."
  value       = module.messaging.delivery_mode
}

output "dead_letter_subscription_name" {
  description = "Inspection subscription of the dead-letter topic."
  value       = module.messaging.dead_letter_subscription_name
}

output "producer_service_account_email" {
  description = "Identity the producer runs as."
  value       = module.messaging.producer_service_account_email
}
