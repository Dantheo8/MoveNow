resource "google_bigquery_dataset" "this" {
  project     = var.project_id
  dataset_id  = var.dataset_id
  location    = var.location
  description = "Dataset des positions des véhicules MoveNow."

  labels = var.labels

  delete_contents_on_destroy = false
}

resource "google_bigquery_table" "this" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.this.dataset_id
  table_id   = var.table_id

  description = "Positions des véhicules reçues depuis Pub/Sub."
  schema      = var.schema
  labels      = var.labels

  time_partitioning {
    type          = "DAY"
    field         = var.partition_field
    expiration_ms = var.retention_days * 24 * 60 * 60 * 1000
  }

  deletion_protection = var.deletion_protection
}