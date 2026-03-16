resource "google_storage_bucket" "this" {
  name                        = var.name
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  versioning {
    enabled = var.versioning_enabled
  }

  dynamic "lifecycle_rule" {
    for_each = var.retention_days > 0 ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        age = var.retention_days
      }
    }
  }

  labels = merge(
    {
      app     = var.app_label
      env     = var.env
      purpose = var.purpose_label
    },
    var.labels
  )
}
