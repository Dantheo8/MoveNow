terraform {
  required_version = ">= 1.16.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.6.0"
    }
  }

  backend "gcs" {
    bucket = "bucket-gcs-movenow"
    prefix = "bootstrap"
  }
}
