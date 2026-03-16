output "name" {
  description = "Bucket name."
  value       = google_storage_bucket.this.name
}

output "uri" {
  description = "Bucket URI."
  value       = "gs://${google_storage_bucket.this.name}"
}
