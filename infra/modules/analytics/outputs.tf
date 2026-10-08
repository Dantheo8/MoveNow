output "dataset_id" {
  description = "Identifiant du dataset BigQuery créé."
  value       = google_bigquery_dataset.this.dataset_id
}

output "table_id" {
  description = "Identifiant court de la table BigQuery créée."
  value       = google_bigquery_table.this.table_id
}

output "table_full_id" {
  description = "Identifiant complet de la table au format projet.dataset.table."
  value = join(".", [
    google_bigquery_table.this.project,
    google_bigquery_table.this.dataset_id,
    google_bigquery_table.this.table_id
  ])
}