variable "project_id" {
  type        = string
  description = "GCP project ID where BigQuery resources are created."
}

variable "dataset_id" {
  type        = string
  description = "BigQuery dataset ID for pipeline operations."
}

variable "location" {
  type        = string
  description = "BigQuery dataset location (for example US or us-central1)."
  default     = "US"
}

variable "dataset_description" {
  type        = string
  description = "Description for the BigQuery dataset."
  default     = "Dataset for AFP to PDF pipeline operations and reporting."
}

variable "create_operations_table" {
  type        = bool
  description = "Whether to create a generic pipeline operations table."
  default     = true
}

variable "operations_table_id" {
  type        = string
  description = "Table ID used for generic pipeline operations metadata."
  default     = "pipeline_operations"
}

variable "operations_table_deletion_protection" {
  type        = bool
  description = "When true, prevents Terraform from deleting the operations table."
  default     = false
}

variable "worker_service_account_email" {
  type        = string
  description = "Service account email used by Linux VMs. Leave blank to skip IAM grants."
  default     = ""
}

variable "worker_dataset_role" {
  type        = string
  description = "Dataset IAM role granted to the worker service account."
  default     = "roles/bigquery.dataEditor"
}

variable "delete_contents_on_destroy" {
  type        = bool
  description = "If true, allows terraform destroy to delete dataset even when not empty."
  default     = true
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to the BigQuery dataset."
  default     = {}
}
