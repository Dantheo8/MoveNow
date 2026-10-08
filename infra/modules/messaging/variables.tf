variable "project_id" {
  description = "GCP project that hosts the Pub/Sub resources."
  type        = string
}

variable "prefix" {
  description = "Group prefix used in every resource name, e.g. g3-movenow."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}[a-z0-9]$", var.prefix))
    error_message = "prefix must be 3 to 21 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "allowed_persistence_regions" {
  description = "Regions where Pub/Sub may store messages. Positions are personal data: keep them in the lab region. Empty list means no restriction."
  type        = list(string)
  default     = []
}

variable "topic_message_retention_duration" {
  description = "How long the topic keeps every message, acknowledged or not, so a subscription can seek back in time to replay. null disables it."
  type        = string
  default     = "86400s"
}

variable "dead_letter_message_retention_duration" {
  description = "How long failed messages stay in the inspection subscription, waiting to be fixed and replayed."
  type        = string
  default     = "604800s"

  validation {
    condition = can(regex("^[0-9]+s$", var.dead_letter_message_retention_duration)) && try(
      tonumber(trimsuffix(var.dead_letter_message_retention_duration, "s")) >= 600 &&
      tonumber(trimsuffix(var.dead_letter_message_retention_duration, "s")) <= 2678400,
    false)
    error_message = "dead_letter_message_retention_duration must be between 600s (10 minutes) and 2678400s (31 days)."
  }
}

variable "producer_impersonators" {
  description = "Members allowed to run the producer as its service account, without any key, e.g. [\"user:first.last@example.com\"]."
  type        = list(string)
  default     = []
}
