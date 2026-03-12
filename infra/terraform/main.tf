terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GCS bucket for processed PDFs (dev)
resource "google_storage_bucket" "pdf_processed" {
  name                        = var.processed_bucket_name
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.processed_pdf_retention_days
    }
  }

  labels = {
    app     = "afp-to-pdf"
    env     = var.env
    purpose = "processed-pdfs"
  }
}