output "dataset_id" {
  description = "Created BigQuery dataset ID."
  value       = google_bigquery_dataset.this.dataset_id
}

output "dataset_fqn" {
  description = "Fully-qualified dataset identifier."
  value       = "${var.project_id}.${google_bigquery_dataset.this.dataset_id}"
}

output "lock_table_id" {
  description = "Created work lock table ID."
  value       = var.create_lock_table ? google_bigquery_table.work_locks[0].table_id : null
}

output "lock_table_fqn" {
  description = "Fully-qualified work lock table identifier."
  value       = var.create_lock_table ? "${var.project_id}.${google_bigquery_dataset.this.dataset_id}.${google_bigquery_table.work_locks[0].table_id}" : null
}
