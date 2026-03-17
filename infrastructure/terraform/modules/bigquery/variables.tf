variable "project_id" {
  type        = string
  description = "GCP project ID where BigQuery resources are created."
}

variable "dataset_id" {
  type        = string
  description = "BigQuery dataset ID for AFP-to-PDF work distribution."
}

variable "location" {
  type        = string
  description = "BigQuery dataset location (for example US or us-central1)."
  default     = "US"
}

variable "dataset_description" {
  type        = string
  description = "Description for the BigQuery dataset."
  default     = "Dataset for AFP-to-PDF work distribution and lock leasing."
}

variable "create_lock_table" {
  type        = bool
  description = "Whether to create the AFP-to-PDF work lock table."
  default     = true
}

variable "lock_table_id" {
  type        = string
  description = "Table ID used for VM work leasing and lock coordination."
  default     = "work_locks"
}

variable "lock_table_deletion_protection" {
  type        = bool
  description = "When true, prevents Terraform from deleting the work lock table."
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
