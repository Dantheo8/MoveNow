terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "google" {
  project = "groupe3inssettp"
}
provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = var.labels
}
