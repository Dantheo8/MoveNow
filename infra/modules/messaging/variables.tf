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

variable "message_retention_duration" {
  description = "How long the main subscription keeps unacknowledged messages: the processing outage the pipeline tolerates without losing data."
  type        = string
  default     = "604800s"

  validation {
    condition = can(regex("^[0-9]+s$", var.message_retention_duration)) && try(
      tonumber(trimsuffix(var.message_retention_duration, "s")) >= 600 &&
      tonumber(trimsuffix(var.message_retention_duration, "s")) <= 2678400,
    false)
    error_message = "message_retention_duration must be between 600s (10 minutes) and 2678400s (31 days)."
  }
}

variable "ack_deadline_seconds" {
  description = "Time a subscriber has to acknowledge a message before Pub/Sub redelivers it."
  type        = number
  default     = 60

  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "ack_deadline_seconds must be between 10 and 600."
  }
}

variable "minimum_backoff" {
  description = "Shortest delay before redelivering a message that failed."
  type        = string
  default     = "10s"
}

variable "maximum_backoff" {
  description = "Longest delay before redelivering a message that failed."
  type        = string
  default     = "600s"
}

variable "max_delivery_attempts" {
  description = "Delivery attempts before a message is moved to the dead-letter topic. Pub/Sub counts them on a best-effort basis."
  type        = number
  default     = 5

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100."
  }
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

variable "bigquery_table" {
  description = "Destination table of the BigQuery subscription. null keeps a plain pull subscription, useful to test the messaging part before the table exists."
  type = object({
    project    = string
    dataset_id = string
    table_id   = string
  })
  default = null
}

variable "bigquery_write_metadata" {
  description = "Also write subscription_name, message_id, publish_time and attributes. The table must then have these columns."
  type        = bool
  default     = false
}

variable "bigquery_drop_unknown_fields" {
  description = "Drop message fields that the table does not have instead of failing the message. Relevant when the mobile team adds fields to the format."
  type        = bool
  default     = false
}

variable "producer_impersonators" {
  description = "Members allowed to run the producer as its service account, without any key, e.g. [\"user:first.last@example.com\"]."
  type        = list(string)
  default     = []
}
