variable "project_id" {
  description = "Identifiant du projet GCP existant."
  type        = string
}

variable "location" {
  description = "Emplacement du dataset BigQuery."
  type        = string
}

variable "dataset_id" {
  description = "Nom du dataset BigQuery."
  type        = string
  default     = "movenow"
}

variable "table_id" {
  description = "Nom de la table des positions."
  type        = string
  default     = "positions"
}

variable "schema" {
  description = "Schéma de la table BigQuery au format JSON."
  type        = string

  validation {
    condition     = can(jsondecode(var.schema))
    error_message = "Le schéma doit être un document JSON valide."
  }
}

variable "partition_field" {
  description = "Champ utilisé pour le partitionnement journalier."
  type        = string
  default     = "event_time"
}

variable "retention_days" {
  description = "Durée de conservation des partitions en jours."
  type        = number
  default     = 7

  validation {
    condition = (
      var.retention_days > 0 &&
      floor(var.retention_days) == var.retention_days
    )
    error_message = "La durée doit être un nombre entier de jours supérieur à zéro."
  }
}

variable "labels" {
  description = "Étiquettes associées aux ressources BigQuery."
  type        = map(string)
  default     = {}
}