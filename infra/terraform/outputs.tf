output "processed_bucket_uri" {
  description = "URI of the processed PDF bucket"
  value       = "gs://${google_storage_bucket.pdf_processed.name}"
}
