output "processed_bucket_uri" {
  description = "URI of the processed PDF bucket"
  value       = module.processed_bucket.uri
}

output "bigquery_dataset_fqn" {
  description = "Fully-qualified BigQuery dataset name for pipeline operations."
  value       = var.enable_bigquery ? module.bigquery[0].dataset_fqn : null
}

output "bigquery_operations_table_fqn" {
  description = "Fully-qualified BigQuery operations table name."
  value       = var.enable_bigquery ? module.bigquery[0].operations_table_fqn : null
}
