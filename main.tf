terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}


provider "google" {
  project = var.project_id
}

module "delivery" {
  source = "./infra/modules/delivery"

  project_id           = var.project_id
  topic_id             = var.topic_id
  table_id             = var.table_id
  dead_letter_topic_id = var.dead_letter_topic_id
  service_agent        = var.service_agent
}
