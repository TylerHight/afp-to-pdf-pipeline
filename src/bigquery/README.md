This folder contains the BigQuery lock-table client used to distribute AFP-to-PDF work across Linux VMs.

## Work model

Each row in the lock table represents one shard of work that a VM can lease:

- one precomputed date-range chunk with a fixed BAN membership list, or
- one input tar file, if tar files are already sized into balanced chunks

For a 12-VM fleet, prefer seeding more than 12 rows. A practical starting point is 60 to 120 lock rows so slow shards do not strand a VM.

For date-range chunking, do not let workers choose "any 25,000 BANs" at claim time. Seed the exact BAN membership list first, write it to GCS, and store that list in `ban_list_uri`.

## Files

- `bq_client.py`
  - `show-config`: resolves `project_id`, dataset, and table using `terraform.tfvars`
  - `create-lock`: inserts one pending work row
  - `list-locks`: lists current lock rows
  - `claim-next`: leases the next available row to a VM
  - `heartbeat`: extends an active lease
  - `complete`: marks a leased row done
  - `fail`: marks a leased row failed and clears the lease
- `create_lock.sh`
- `list_locks.sh`
- `claim_lock.sh`
- `heartbeat_lock.sh`
- `complete_lock.sh`
- `fail_lock.sh`

## Table shape

The Terraform-managed table defaults to `work_locks` and includes:

- workload identity: `lock_id`, `work_type`, `shard_key`
- business partitioning: `date_range_start`, `date_range_end`, `target_ban_count`, `selected_ban_count`, `chunk_index`
- deterministic membership: `ban_list_uri`
- storage routing: `source_uri`, `destination_prefix`
- lease control: `status`, `lease_owner`, `lease_token`, `lease_expires_at`, `last_heartbeat_at`
- retry and audit fields: `priority`, `attempt_count`, `max_attempts`, `last_error`, `created_at`, `updated_at`, `completed_at`
- `metadata_json` for tar members, invoice month, or other shard details

## Defaults

By default, values are read from `infrastructure/terraform/terraform.tfvars`:

- `project_id`
- `bigquery_dataset_id`
- `bigquery_lock_table_id`

You can override any value with CLI flags: `--project-id`, `--dataset-id`, `--table-id`.

## Quick usage

```bash
# show resolved target
python ./src/bigquery/bq_client.py show-config

# seed one shard
bash ./src/bigquery/create_lock.sh \
  --shard-key 2026-03-01_to_2026-03-03_chunk_000 \
  --date-range-start 2026-03-01 \
  --date-range-end 2026-03-03 \
  --target-ban-count 25000 \
  --selected-ban-count 24871 \
  --chunk-index 0 \
  --ban-list-uri gs://afp-input/manifests/2026-03-01_to_2026-03-03/chunk-000.json \
  --source-uri gs://afp-input/monthly/2026-03/day-01.tar \
  --destination-prefix gs://afp-output/monthly/2026-03/day-01/

# claim work on a VM
bash ./src/bigquery/claim_lock.sh --lease-owner vm-03 --lease-seconds 900

# extend the lease while the VM is converting AFP files
bash ./src/bigquery/heartbeat_lock.sh --lock-id <lock_id> --lease-token <lease_token>

# finish or fail the shard
bash ./src/bigquery/complete_lock.sh --lock-id <lock_id> --lease-token <lease_token>
bash ./src/bigquery/fail_lock.sh --lock-id <lock_id> --lease-token <lease_token> --error-message "tar extraction failed"
```

## Requirements

- Python 3
- `google-cloud-bigquery` installed
- GCP credentials configured, for example with `gcloud auth application-default login`
