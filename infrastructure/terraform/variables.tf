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