variable "project_id" {
  description = "GCP project of the lab, given by the instructor."
  type        = string
}

variable "region" {
  description = "Region of the lab. Pub/Sub messages are only stored there."
  type        = string
  default     = "europe-west9"
}

variable "prefix" {
  description = "Group prefix used in every resource name, e.g. g3-movenow."
  type        = string
}

variable "labels" {
  description = "Labels put on every resource, as required by the instructor."
  type        = map(string)
  default = {
    project     = "movenow"
    group       = "g3"
    environment = "lab"
    managed_by  = "terraform"
  }

  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Label keys and values must be lowercase letters, digits, _ or -, and keys must start with a letter."
  }
}

variable "message_retention_duration" {
  description = "Processing outage the pipeline tolerates without losing messages (main subscription retention)."
  type        = string
  default     = "604800s"
}

variable "max_delivery_attempts" {
  description = "Delivery attempts before a message goes to the dead-letter topic."
  type        = number
  default     = 5
}

variable "bigquery_table" {
  description = "Destination table of the positions. Leave null until the table exists: the main subscription stays a pull subscription."
  type = object({
    project    = string
    dataset_id = string
    table_id   = string
  })
  default = null
}

variable "producer_impersonators" {
  description = "Team members allowed to run the producer as its service account, e.g. [\"user:first.last@example.com\"]."
  type        = list(string)
  default     = []
}
