This folder contains the BigQuery lock-table client used to distribute AFP-to-PDF work across Linux VMs.

## Work model

Each row in the lock table represents one shard of work that a VM can lease:

- one invoice-day slice for a BAN range, or
- one input tar file, if tar files are already sized into balanced chunks

For a 12-VM fleet, prefer seeding more than 12 rows. A practical starting point is 60 to 120 lock rows so slow shards do not strand a VM.

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
- business partitioning: `billing_cycle_date`, `ban_range_start`, `ban_range_end`, `ban_count`
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
  --shard-key 2026-03-01-ban-bucket-01 \
  --billing-cycle-date 2026-03-01 \
  --ban-range-start 10000000 \
  --ban-range-end 10024999 \
  --ban-count 25000 \
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
