variable "project_id" {
  description = "Projet GCP qui heberge le dashboard et les alertes."
  type        = string
}

variable "topic_id" {
  description = "Nom complet du topic de positions, pour afficher les publications."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/topics/[^/]+$", var.topic_id))
    error_message = "topic_id doit avoir la forme projects/PROJET/topics/NOM."
  }
}

variable "subscription_ids" {
  description = "Noms complets des subscriptions d'export et d'inspection dead-letter."
  type = object({
    export      = string
    dead_letter = string
  })

  validation {
    condition = alltrue([
      for id in values(var.subscription_ids) : can(regex("^projects/[^/]+/subscriptions/[^/]+$", id))
    ])
    error_message = "Chaque subscription doit avoir la forme projects/PROJET/subscriptions/NOM."
  }
}

variable "backlog_threshold" {
  description = "Nombre de messages en attente au-dessus duquel alerter pendant 5 minutes."
  type        = number
  default     = 100
}

variable "oldest_message_age_threshold_seconds" {
  description = "Age maximal du plus ancien message, en secondes, pendant 5 minutes."
  type        = number
  default     = 300
}

variable "dead_letter_threshold" {
  description = "Nombre de transferts dead-letter au-dessus duquel alerter sur 5 minutes."
  type        = number
  default     = 0
}

variable "notification_channels" {
  description = "Noms complets des canaux Cloud Monitoring existants. Liste vide : incidents sans notification."
  type        = list(string)
  default     = []
}
