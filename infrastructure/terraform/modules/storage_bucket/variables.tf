variable "name" {
  type        = string
  description = "Globally unique GCS bucket name."
}

variable "location" {
  type        = string
  description = "GCS bucket location."
}

variable "storage_class" {
  type        = string
  description = "Bucket storage class."
  default     = "STANDARD"
}

variable "env" {
  type        = string
  description = "Environment label value."
}

variable "purpose_label" {
  type        = string
  description = "Purpose label value."
}

variable "app_label" {
  type        = string
  description = "App label value."
  default     = "afp-to-pdf"
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable object versioning."
  default     = true
}

variable "retention_days" {
  type        = number
  description = "Delete objects older than this many days. Set 0 to disable lifecycle deletion."
  default     = 0
}

variable "force_destroy" {
  type        = bool
  description = "Allow bucket deletion even if non-empty."
  default     = false
}

variable "labels" {
  type        = map(string)
  description = "Additional labels."
  default     = {}
}
