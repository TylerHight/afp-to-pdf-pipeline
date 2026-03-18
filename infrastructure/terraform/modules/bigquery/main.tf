resource "google_bigquery_dataset" "this" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  location                   = var.location
  description                = var.dataset_description
  delete_contents_on_destroy = var.delete_contents_on_destroy

  labels = var.labels
}

resource "google_bigquery_table" "work_locks" {
  count = var.create_lock_table ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.this.dataset_id
  table_id            = var.lock_table_id
  deletion_protection = var.lock_table_deletion_protection

  description = "Lease-based work distribution table for AFP-to-PDF worker VMs."

  schema = jsonencode([
    {
      name = "lock_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "work_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "shard_key"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "date_range_start"
      type = "DATE"
      mode = "NULLABLE"
    },
    {
      name = "date_range_end"
      type = "DATE"
      mode = "NULLABLE"
    },
    {
      name = "target_ban_count"
      type = "INT64"
      mode = "NULLABLE"
    },
    {
      name = "selected_ban_count"
      type = "INT64"
      mode = "NULLABLE"
    },
    {
      name = "chunk_index"
      type = "INT64"
      mode = "NULLABLE"
    },
    {
      name = "ban_list_uri"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "source_uri"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "destination_prefix"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "priority"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "attempt_count"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "max_attempts"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "lease_owner"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "lease_token"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "lease_expires_at"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "claimed_at"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "last_heartbeat_at"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "completed_at"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "last_error"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "metadata_json"
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
