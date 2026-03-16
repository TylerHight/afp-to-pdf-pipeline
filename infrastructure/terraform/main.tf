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

module "processed_bucket" {
  source = "./modules/storage_bucket"

  name               = var.processed_bucket_name
  location           = var.location
  storage_class      = var.storage_class
  env                = var.env
  purpose_label      = "processed-pdfs"
  retention_days     = var.processed_pdf_retention_days
  force_destroy      = var.processed_bucket_force_destroy
  labels             = var.processed_bucket_labels
  app_label          = "afp-to-pdf"
  versioning_enabled = true
}

module "bigquery" {
  count  = var.enable_bigquery ? 1 : 0
  source = "./modules/bigquery"

  project_id                           = var.project_id
  dataset_id                           = var.bigquery_dataset_id
  location                             = var.bigquery_location
  dataset_description                  = var.bigquery_dataset_description
  create_operations_table              = var.bigquery_create_operations_table
  operations_table_id                  = var.bigquery_operations_table_id
  operations_table_deletion_protection = var.bigquery_operations_table_deletion_protection
  worker_service_account_email         = var.bigquery_worker_service_account_email
  worker_dataset_role                  = var.bigquery_worker_dataset_role
  delete_contents_on_destroy           = var.bigquery_delete_contents_on_destroy

  labels = {
    app     = "afp-to-pdf"
    env     = var.env
    purpose = "pipeline-ops"
  }
}
