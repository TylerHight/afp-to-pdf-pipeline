output "dataset_id" {
  description = "Created BigQuery dataset ID."
  value       = google_bigquery_dataset.this.dataset_id
}

output "dataset_fqn" {
  description = "Fully-qualified dataset identifier."
  value       = "${var.project_id}.${google_bigquery_dataset.this.dataset_id}"
}

output "operations_table_id" {
  description = "Created pipeline operations table ID."
  value       = var.create_operations_table ? google_bigquery_table.pipeline_operations[0].table_id : null
}

output "operations_table_fqn" {
  description = "Fully-qualified pipeline operations table identifier."
  value       = var.create_operations_table ? "${var.project_id}.${google_bigquery_dataset.this.dataset_id}.${google_bigquery_table.pipeline_operations[0].table_id}" : null
}
