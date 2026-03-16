variable "project_id" {
  type        = string
  description = "GCP project ID (e.g., my-gcp-project)"
}

variable "region" {
  type        = string
  description = "Default region for provider operations"
  default     = "us-central1"
}

variable "location" {
  type        = string
  description = "Bucket location/region (e.g., us-central1, us, northamerica-northeast1)"
  default     = "us-central1"
}

variable "storage_class" {
  type        = string
  description = "Storage class for the bucket (STANDARD, NEARLINE, COLDLINE, ARCHIVE)"
  default     = "STANDARD"
}

variable "env" {
  type        = string
  description = "Environment tag (dev/test/prod)"
  default     = "dev"
}

variable "processed_bucket_name" {
  type        = string
  description = "Globally-unique bucket name for processed PDFs (e.g., afp-pdfs-dev-<uniq>)"
}

variable "processed_pdf_retention_days" {
  type        = number
  description = "Days to retain processed PDFs before auto-delete (set high or 0 to disable rule)"
  default     = 0
}

variable "processed_bucket_force_destroy" {
  type        = bool
  description = "Allow terraform to delete processed bucket even when non-empty."
  default     = false
}

variable "processed_bucket_labels" {
  type        = map(string)
  description = "Additional labels applied to the processed bucket."
  default     = {}
}

variable "enable_bigquery" {
  type        = bool
  description = "Whether to create BigQuery resources for pipeline operations."
  default     = true
}

variable "bigquery_dataset_id" {
  type        = string
  description = "BigQuery dataset ID for pipeline operations metadata."
  default     = "afp_pdf_poc"
}

variable "bigquery_location" {
  type        = string
  description = "BigQuery location (for example US or us-central1)."
  default     = "US"
}

variable "bigquery_dataset_description" {
  type        = string
  description = "Description for the BigQuery dataset."
  default     = "Dataset for AFP to PDF pipeline operations and reporting."
}

variable "bigquery_create_operations_table" {
  type        = bool
  description = "Whether to create a generic pipeline operations table."
  default     = true
}

variable "bigquery_operations_table_id" {
  type        = string
  description = "Table ID for the generic pipeline operations table."
  default     = "pipeline_operations"
}

variable "bigquery_operations_table_deletion_protection" {
  type        = bool
  description = "When true, prevents Terraform from deleting the BigQuery operations table."
  default     = false
}

variable "bigquery_worker_service_account_email" {
  type        = string
  description = "Service account email used by worker VMs for BigQuery access."
  default     = ""
}

variable "bigquery_worker_dataset_role" {
  type        = string
  description = "Dataset-level role granted to worker VM service account."
  default     = "roles/bigquery.dataEditor"
}

variable "bigquery_delete_contents_on_destroy" {
  type        = bool
  description = "Allow terraform destroy to delete BigQuery dataset even if it contains tables/data."
  default     = true
}
