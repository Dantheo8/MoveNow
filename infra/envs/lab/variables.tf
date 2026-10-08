variable "project_id" {
  description = "GCP project of the lab, given by the instructor."
  type        = string
  default     = "groupe3inssettp"
}

variable "region" {
  description = "Region of the lab. Pub/Sub messages are only stored there."
  type        = string
  default     = "europe-west9"
}

variable "prefix" {
  description = "Group prefix used in every resource name, e.g. g3-movenow."
  type        = string
  default     = "g3-movenow"
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
  description = "Processing outage the pipeline tolerates without losing messages: retention of the BigQuery subscription."
  type        = string
  default     = "604800s"
}

variable "max_delivery_attempts" {
  description = "Delivery attempts before a message goes to the dead-letter topic."
  type        = number
  default     = 5
}

variable "dataset_id" {
  description = "BigQuery dataset holding the positions table."
  type        = string
  default     = "movenow"
}

variable "retention_days" {
  description = "Days of position history kept in BigQuery, from the scoping step."
  type        = number
  default     = 7
}

variable "table_deletion_protection" {
  description = "Prevent Terraform from deleting the positions table. Off in the lab, which must be destroyed at the end."
  type        = bool
  default     = false
}

variable "producer_impersonators" {
  description = "Team members allowed to run the producer as its service account, e.g. [\"user:first.last@example.com\"]."
  type        = list(string)
  default     = []
}

variable "notification_channels" {
  description = "Full names of existing Cloud Monitoring notification channels. Empty list creates alerts without notifications."
  type        = list(string)
  default     = []
}
