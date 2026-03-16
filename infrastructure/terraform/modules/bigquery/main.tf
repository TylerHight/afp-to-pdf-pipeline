resource "google_bigquery_dataset" "this" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  location                   = var.location
  description                = var.dataset_description
  delete_contents_on_destroy = var.delete_contents_on_destroy

  labels = var.labels
}

resource "google_bigquery_table" "pipeline_operations" {
  count = var.create_operations_table ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.this.dataset_id
  table_id            = var.operations_table_id
  deletion_protection = var.operations_table_deletion_protection

  description = "Generic pipeline operations table for lightweight metadata and audit events."

  schema = jsonencode([
    {
      name = "operation_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "operation_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "source_system"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "details_json"
      type = "JSON"
      mode = "NULLABLE"
    },
    {
      name = "created_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "updated_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    }
  ])
}

resource "google_bigquery_dataset_iam_member" "worker_dataset_access" {
  count      = var.worker_service_account_email == "" ? 0 : 1
  dataset_id = google_bigquery_dataset.this.dataset_id
  project    = var.project_id
  role       = var.worker_dataset_role
  member     = "serviceAccount:${var.worker_service_account_email}"
}

resource "google_project_iam_member" "worker_job_user" {
  count   = var.worker_service_account_email == "" ? 0 : 1
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.worker_service_account_email}"
}
