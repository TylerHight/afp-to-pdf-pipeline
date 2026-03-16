This folder holds minimal proof-of-concept logic for interacting with BigQuery.

## What was added

- `bq_client.py`
  - `show-config`: resolves `project_id`, dataset, and table using `terraform.tfvars` defaults.
  - `insert-demo`: inserts one row into the Terraform-defined `pipeline_operations` table.
  - `query-recent`: fetches recent rows from that same table.
- `insert_demo_operation.sh`
  - Shell wrapper for `bq_client.py insert-demo`.
- `query_recent_operations.sh`
  - Shell wrapper for `bq_client.py query-recent`.

## Defaults

By default, values are read from:

- `infrastructure/terraform/terraform.tfvars`

Specifically:

- `project_id`
- `bigquery_dataset_id`
- `bigquery_operations_table_id`

You can override any value with CLI flags (`--project-id`, `--dataset-id`, `--table-id`).

## Quick usage

```bash
# show resolved table target
python ./src/bigquery/bq_client.py show-config

# insert one demo row
bash ./src/bigquery/insert_demo_operation.sh

# query last 10 rows
bash ./src/bigquery/query_recent_operations.sh --limit 10
```

## Requirements

- Python 3
- `google-cloud-bigquery` installed
- GCP credentials configured (for example via `gcloud auth application-default login`)
