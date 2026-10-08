variable "project_id" {
  description = "Projet GCP qui héberge la subscription de transfert."
  type        = string
}

variable "subscription_name" {
  description = "Nom court de la subscription BigQuery."
  type        = string
  default     = "positions-vers-bigquery"
}

variable "topic_id" {
  description = "Nom complet du topic source : projects/PROJET/topics/TOPIC."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/topics/[^/]+$", var.topic_id))
    error_message = "topic_id doit avoir la forme projects/PROJET/topics/TOPIC."
  }
}

variable "table_id" {
  description = "Identifiant complet de la table BigQuery : PROJET.DATASET.TABLE."
  type        = string

  validation {
    condition     = can(regex("^[^.]+\\.[^.]+\\.[^.]+$", var.table_id))
    error_message = "table_id doit avoir la forme PROJET.DATASET.TABLE."
  }
}

variable "dead_letter_topic_id" {
  description = "Nom complet du topic dead-letter : projects/PROJET/topics/TOPIC."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/topics/[^/]+$", var.dead_letter_topic_id))
    error_message = "dead_letter_topic_id doit avoir la forme projects/PROJET/topics/TOPIC."
  }
}

variable "service_agent" {
  description = "Adresse e-mail du service agent Pub/Sub du projet de la subscription."
  type        = string

  validation {
    condition     = can(regex("^service-[0-9]+@gcp-sa-pubsub\\.iam\\.gserviceaccount\\.com$", var.service_agent))
    error_message = "service_agent doit être l'adresse du service agent Pub/Sub."
  }
}

variable "retry_minimum_backoff" {
  description = "Délai minimal entre deux tentatives de livraison."
  type        = string
  default     = "10s"
}

variable "retry_maximum_backoff" {
  description = "Délai maximal entre deux tentatives de livraison."
  type        = string
  default     = "600s"
}

variable "max_delivery_attempts" {
  description = "Nombre maximal de tentatives avant transfert vers la dead-letter."
  type        = number
  default     = 5

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "max_delivery_attempts doit être compris entre 5 et 100."
  }
}
