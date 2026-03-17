output "processed_bucket_uri" {
  description = "URI of the processed PDF bucket"
  value       = module.processed_bucket.uri
}

output "bigquery_dataset_fqn" {
  description = "Fully-qualified BigQuery dataset name for work distribution."
  value       = var.enable_bigquery ? module.bigquery[0].dataset_fqn : null
}

output "bigquery_lock_table_fqn" {
  description = "Fully-qualified BigQuery work lock table name."
  value       = var.enable_bigquery ? module.bigquery[0].lock_table_fqn : null
}
