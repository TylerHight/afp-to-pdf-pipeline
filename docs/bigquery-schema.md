# BigQuery Schema Specification

## Purpose

This document defines the exact schemas for the BigQuery tables used in the AFP-to-PDF pipeline, including field meanings, required vs nullable constraints, and example rows.

This turns architecture into implementation by providing the precise data contracts needed to build the planner, workers, and reporting views.

## Scope

This document covers:

- `work_locks` table schema
- `conversion_results` table schema
- recommended reporting views
- field meanings and constraints
- partitioning and clustering recommendations
- example rows for each table

This document does not cover:

- BigQuery dataset-level IAM policies (that is an infrastructure concern)
- query optimization beyond basic clustering
- data retention policies

## Dataset

Recommended dataset name:

```text
afp_pipeline
```

Full table references:

- `project.afp_pipeline.work_locks`
- `project.afp_pipeline.conversion_results`

## Table 1: `work_locks`

### Purpose

The `work_locks` table is the coordination table for chunk leasing and worker assignment.

It holds one row per deterministic chunk and tracks:

- chunk identity and metadata
- current lease ownership
- lease expiry
- retry state
- completion status

### Schema

```sql
CREATE TABLE `project.afp_pipeline.work_locks` (
  lock_id STRING NOT NULL,
  shard_key STRING NOT NULL,
  date_range_start DATE NOT NULL,
  date_range_end DATE NOT NULL,
  target_ban_count INT64 NOT NULL,
  selected_ban_count INT64 NOT NULL,
  chunk_index INT64 NOT NULL,
  ban_list_uri STRING NOT NULL,
  priority INT64 NOT NULL,
  status STRING NOT NULL,
  worker_id STRING,
  lease_token STRING,
  lease_expires_at TIMESTAMP,
  attempt_count INT64 NOT NULL DEFAULT 0,
  max_attempts INT64 NOT NULL DEFAULT 3,
  metadata_json STRING,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  completed_at TIMESTAMP
)
PARTITION BY DATE(created_at)
CLUSTER BY status, priority, date_range_start;
```

### Field Definitions

#### `lock_id`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Unique identifier for this lock row. Should be a UUID or similar globally unique value.
- **Example**: `"550e8400-e29b-41d4-a716-446655440000"`

#### `shard_key`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Human-readable deterministic key for the chunk. Used for idempotency and debugging.
- **Format**: `<processing-month>_<date-range-start>_<date-range-end>_chunk_<chunk-index>`
- **Example**: `"2026-03_2026-03-01_2026-03-03_chunk_0000"`
- **Constraint**: Should be unique across all rows.

#### `date_range_start`

- **Type**: `DATE`
- **Required**: Yes
- **Meaning**: Start date of the billing day window for this chunk (inclusive).
- **Example**: `2026-03-01`

#### `date_range_end`

- **Type**: `DATE`
- **Required**: Yes
- **Meaning**: End date of the billing day window for this chunk (inclusive).
- **Example**: `2026-03-03`

#### `target_ban_count`

- **Type**: `INT64`
- **Required**: Yes
- **Meaning**: The intended maximum number of BANs per chunk, as configured by the planner.
- **Example**: `25000`

#### `selected_ban_count`

- **Type**: `INT64`
- **Required**: Yes
- **Meaning**: The actual number of BANs assigned to this chunk by the planner.
- **Example**: `24871`
- **Constraint**: `selected_ban_count <= target_ban_count`

#### `chunk_index`

- **Type**: `INT64`
- **Required**: Yes
- **Meaning**: Zero-based index of this chunk within the same date range window.
- **Example**: `0`, `1`, `2`

#### `ban_list_uri`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: GCS URI of the chunk manifest JSON file.
- **Example**: `"gs://afp-input/manifests/2026-03/2026-03-01_2026-03-03/chunk-0000.json"`

#### `priority`

- **Type**: `INT64`
- **Required**: Yes
- **Meaning**: Priority for worker claim ordering. Higher values are claimed first.
- **Example**: `202603000` (derived from `YYYYMM * 100000 - chunk_index`)

#### `status`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Current state of the chunk.
- **Allowed Values**:
  - `PENDING`: chunk is available for claim
  - `LEASED`: chunk is currently leased to a worker
  - `DONE`: chunk completed successfully
  - `FAILED`: chunk failed after max attempts or terminal error
- **Example**: `"PENDING"`

#### `worker_id`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: Identifier of the worker VM that currently holds or last held the lease.
- **Example**: `"worker-vm-01"`, `"afp-worker-us-central1-a-001"`
- **Constraint**: Should be null when `status = PENDING`.

#### `lease_token`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: Unique token for the current lease. Used to prevent stale workers from completing chunks they no longer own.
- **Example**: `"lease-550e8400-e29b-41d4-a716-446655440000"`
- **Constraint**: Should be null when `status = PENDING` or `status = DONE` or `status = FAILED`.

#### `lease_expires_at`

- **Type**: `TIMESTAMP`
- **Required**: No (nullable)
- **Meaning**: UTC timestamp when the current lease expires. After this time, the chunk becomes eligible for reclaim.
- **Example**: `2026-03-18T12:15:00Z`
- **Constraint**: Should be null when `status = PENDING` or `status = DONE` or `status = FAILED`.

#### `attempt_count`

- **Type**: `INT64`
- **Required**: Yes
- **Default**: `0`
- **Meaning**: Number of times this chunk has been claimed (including the current attempt if leased).
- **Example**: `0`, `1`, `2`

#### `max_attempts`

- **Type**: `INT64`
- **Required**: Yes
- **Default**: `3`
- **Meaning**: Maximum number of attempts allowed before the chunk is marked as terminally failed.
- **Example**: `3`

#### `metadata_json`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: JSON-encoded metadata from the planner, including processing month, planning run ID, expected conversion count, manifest checksum, planner version, and routing rules version.
- **Example**: `{"processing_month":"2026-03","planning_run_id":"2026-03-18T03:15:00Z","expected_conversion_count":24871,"manifest_checksum":"sha256:...","planner_version":"v1","routing_rules_version":"v1"}`

#### `created_at`

- **Type**: `TIMESTAMP`
- **Required**: Yes
- **Meaning**: UTC timestamp when the planner created this lock row.
- **Example**: `2026-03-18T03:15:00Z`

#### `updated_at`

- **Type**: `TIMESTAMP`
- **Required**: Yes
- **Meaning**: UTC timestamp of the last update to this row (claim, heartbeat, complete, fail).
- **Example**: `2026-03-18T12:30:00Z`

#### `completed_at`

- **Type**: `TIMESTAMP`
- **Required**: No (nullable)
- **Meaning**: UTC timestamp when the chunk was marked `DONE` or `FAILED`.
- **Example**: `2026-03-18T12:45:00Z`
- **Constraint**: Should be null when `status = PENDING` or `status = LEASED`.

### Partitioning And Clustering

**Partition by**: `DATE(created_at)`

**Cluster by**: `status`, `priority`, `date_range_start`

**Rationale**:

- Partitioning by creation date helps with data lifecycle management and query performance for recent chunks.
- Clustering by `status` optimizes worker queries for available chunks.
- Clustering by `priority` optimizes claim ordering.
- Clustering by `date_range_start` optimizes reporting queries by date range.

### Example Rows

#### Example 1: Pending Chunk

```json
{
  "lock_id": "550e8400-e29b-41d4-a716-446655440000",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0000",
  "date_range_start": "2026-03-01",
  "date_range_end": "2026-03-03",
  "target_ban_count": 25000,
  "selected_ban_count": 24871,
  "chunk_index": 0,
  "ban_list_uri": "gs://afp-input/manifests/2026-03/2026-03-01_2026-03-03/chunk-0000.json",
  "priority": 202603000,
  "status": "PENDING",
  "worker_id": null,
  "lease_token": null,
  "lease_expires_at": null,
  "attempt_count": 0,
  "max_attempts": 3,
  "metadata_json": "{\"processing_month\":\"2026-03\",\"planning_run_id\":\"2026-03-18T03:15:00Z\",\"expected_conversion_count\":24871,\"manifest_checksum\":\"sha256:abc123\",\"planner_version\":\"v1\",\"routing_rules_version\":\"v1\"}",
  "created_at": "2026-03-18T03:15:00Z",
  "updated_at": "2026-03-18T03:15:00Z",
  "completed_at": null
}
```

#### Example 2: Leased Chunk

```json
{
  "lock_id": "550e8400-e29b-41d4-a716-446655440001",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0001",
  "date_range_start": "2026-03-01",
  "date_range_end": "2026-03-03",
  "target_ban_count": 25000,
  "selected_ban_count": 25000,
  "chunk_index": 1,
  "ban_list_uri": "gs://afp-input/manifests/2026-03/2026-03-01_2026-03-03/chunk-0001.json",
  "priority": 202602999,
  "status": "LEASED",
  "worker_id": "worker-vm-01",
  "lease_token": "lease-550e8400-e29b-41d4-a716-446655440001",
  "lease_expires_at": "2026-03-18T12:25:00Z",
  "attempt_count": 1,
  "max_attempts": 3,
  "metadata_json": "{\"processing_month\":\"2026-03\",\"planning_run_id\":\"2026-03-18T03:15:00Z\",\"expected_conversion_count\":25000,\"manifest_checksum\":\"sha256:def456\",\"planner_version\":\"v1\",\"routing_rules_version\":\"v1\"}",
  "created_at": "2026-03-18T03:15:00Z",
  "updated_at": "2026-03-18T12:15:00Z",
  "completed_at": null
}
```

#### Example 3: Completed Chunk

```json
{
  "lock_id": "550e8400-e29b-41d4-a716-446655440002",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0002",
  "date_range_start": "2026-03-01",
  "date_range_end": "2026-03-03",
  "target_ban_count": 25000,
  "selected_ban_count": 23456,
  "chunk_index": 2,
  "ban_list_uri": "gs://afp-input/manifests/2026-03/2026-03-01_2026-03-03/chunk-0002.json",
  "priority": 202602998,
  "status": "DONE",
  "worker_id": "worker-vm-02",
  "lease_token": null,
  "lease_expires_at": null,
  "attempt_count": 1,
  "max_attempts": 3,
  "metadata_json": "{\"processing_month\":\"2026-03\",\"planning_run_id\":\"2026-03-18T03:15:00Z\",\"expected_conversion_count\":23456,\"manifest_checksum\":\"sha256:ghi789\",\"planner_version\":\"v1\",\"routing_rules_version\":\"v1\"}",
  "created_at": "2026-03-18T03:15:00Z",
  "updated_at": "2026-03-18T12:45:00Z",
  "completed_at": "2026-03-18T12:45:00Z"
}
```

#### Example 4: Failed Chunk

```json
{
  "lock_id": "550e8400-e29b-41d4-a716-446655440003",
  "shard_key": "2026-03_2026-03-04_2026-03-06_chunk_0000",
  "date_range_start": "2026-03-04",
  "date_range_end": "2026-03-06",
  "target_ban_count": 25000,
  "selected_ban_count": 24500,
  "chunk_index": 0,
  "ban_list_uri": "gs://afp-input/manifests/2026-03/2026-03-04_2026-03-06/chunk-0000.json",
  "priority": 202603000,
  "status": "FAILED",
  "worker_id": "worker-vm-03",
  "lease_token": null,
  "lease_expires_at": null,
  "attempt_count": 3,
  "max_attempts": 3,
  "metadata_json": "{\"processing_month\":\"2026-03\",\"planning_run_id\":\"2026-03-18T03:15:00Z\",\"expected_conversion_count\":24500,\"manifest_checksum\":\"sha256:jkl012\",\"planner_version\":\"v1\",\"routing_rules_version\":\"v1\"}",
  "created_at": "2026-03-18T03:15:00Z",
  "updated_at": "2026-03-18T14:30:00Z",
  "completed_at": "2026-03-18T14:30:00Z"
}
```

## Table 2: `conversion_results`

### Purpose

The `conversion_results` table is the append-only reporting table for individual conversion attempts.

It holds one row per attempted conversion unit and tracks:

- conversion identity and source
- destination output
- worker and attempt metadata
- result status and failure details
- timing and validation metadata

### Schema

```sql
CREATE TABLE `project.afp_pipeline.conversion_results` (
  result_id STRING NOT NULL,
  lock_id STRING NOT NULL,
  shard_key STRING NOT NULL,
  planning_run_id STRING NOT NULL,
  processing_month STRING NOT NULL,
  statement_date DATE NOT NULL,
  ban STRING NOT NULL,
  source_tar_uri STRING NOT NULL,
  source_member_path STRING NOT NULL,
  destination_uri STRING,
  worker_id STRING NOT NULL,
  attempt_number INT64 NOT NULL,
  result_status STRING NOT NULL,
  failure_code STRING,
  failure_message STRING,
  converter_exit_code INT64,
  output_bytes INT64,
  output_sha256 STRING,
  started_at TIMESTAMP NOT NULL,
  completed_at TIMESTAMP NOT NULL,
  inserted_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(inserted_at)
CLUSTER BY processing_month, result_status, worker_id, shard_key;
```

### Field Definitions

#### `result_id`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Unique identifier for this result row. Should be a UUID or similar globally unique value.
- **Example**: `"650e8400-e29b-41d4-a716-446655440000"`

#### `lock_id`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Foreign key to `work_locks.lock_id`. Ties this result back to the chunk.
- **Example**: `"550e8400-e29b-41d4-a716-446655440000"`

#### `shard_key`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Human-readable chunk identifier. Copied from `work_locks.shard_key`.
- **Example**: `"2026-03_2026-03-01_2026-03-03_chunk_0000"`

#### `planning_run_id`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Identifier of the planning run that created this chunk. Copied from `work_locks.metadata_json`.
- **Example**: `"2026-03-18T03:15:00Z"`

#### `processing_month`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Processing month in `YYYY-MM` format.
- **Example**: `"2026-03"`

#### `statement_date`

- **Type**: `DATE`
- **Required**: Yes
- **Meaning**: Billing day or statement date for this conversion unit.
- **Example**: `2026-03-01`

#### `ban`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Billing Account Number for this conversion unit.
- **Example**: `"10000001"`

#### `source_tar_uri`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: GCS URI of the source tar file containing the AFP member.
- **Example**: `"gs://afp-input/monthly/2026-03/day-01.tar"`

#### `source_member_path`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Path or name of the AFP member within the tar file.
- **Example**: `"batch001/10000001_20260301.afp"`

#### `destination_uri`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: GCS URI of the output PDF. Should be present on `SUCCESS` and `SKIPPED`, null on `FAILED`.
- **Example**: `"gs://afp-output-residential/invoices/2026-03/10000001_20260301.pdf"`

#### `worker_id`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Identifier of the worker VM that processed this conversion.
- **Example**: `"worker-vm-01"`

#### `attempt_number`

- **Type**: `INT64`
- **Required**: Yes
- **Meaning**: Attempt number for this conversion unit within the chunk. Increments on retry.
- **Example**: `1`, `2`, `3`

#### `result_status`

- **Type**: `STRING`
- **Required**: Yes
- **Meaning**: Result of the conversion attempt.
- **Allowed Values**:
  - `SUCCESS`: conversion succeeded and PDF was uploaded
  - `FAILED`: conversion failed
  - `SKIPPED`: conversion was skipped because a valid output already existed
- **Example**: `"SUCCESS"`

#### `failure_code`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: Structured failure code. Should be present on `FAILED`, null on `SUCCESS` and `SKIPPED`.
- **Allowed Values**: `BAD_TAR`, `BAD_AFP`, `CONVERTER_ERROR`, `OUTPUT_VALIDATION_FAILED`, `UPLOAD_FAILED`, `MANIFEST_ERROR`, `LEASE_LOST`, `NO_ROUTING_RULE`, `ROUTING_TEMPLATE_ERROR`, `UNKNOWN`
- **Example**: `"CONVERTER_ERROR"`

#### `failure_message`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: Human-readable failure message. Should be present on `FAILED`, null on `SUCCESS` and `SKIPPED`.
- **Example**: `"Converter exited with code 1: unsupported AFP version"`

#### `converter_exit_code`

- **Type**: `INT64`
- **Required**: No (nullable)
- **Meaning**: Exit code from the converter binary. Should be present when converter was invoked.
- **Example**: `0` (success), `1` (error)

#### `output_bytes`

- **Type**: `INT64`
- **Required**: No (nullable)
- **Meaning**: Size of the output PDF in bytes. Should be present on `SUCCESS`.
- **Example**: `524288`

#### `output_sha256`

- **Type**: `STRING`
- **Required**: No (nullable)
- **Meaning**: SHA-256 checksum of the output PDF. Should be present on `SUCCESS` if computed.
- **Example**: `"sha256:abc123def456..."`

#### `started_at`

- **Type**: `TIMESTAMP`
- **Required**: Yes
- **Meaning**: UTC timestamp when the conversion attempt started.
- **Example**: `2026-03-18T12:15:00Z`

#### `completed_at`

- **Type**: `TIMESTAMP`
- **Required**: Yes
- **Meaning**: UTC timestamp when the conversion attempt completed (success or failure).
- **Example**: `2026-03-18T12:15:30Z`

#### `inserted_at`

- **Type**: `TIMESTAMP`
- **Required**: Yes
- **Meaning**: UTC timestamp when this row was inserted into BigQuery.
- **Example**: `2026-03-18T12:15:31Z`

### Partitioning And Clustering

**Partition by**: `DATE(inserted_at)`

**Cluster by**: `processing_month`, `result_status`, `worker_id`, `shard_key`

**Rationale**:

- Partitioning by insertion date helps with data lifecycle management and query performance for recent results.
- Clustering by `processing_month` optimizes reporting queries by month.
- Clustering by `result_status` optimizes queries for success/failure counts.
- Clustering by `worker_id` optimizes worker throughput queries.
- Clustering by `shard_key` optimizes chunk-level progress queries.

### Example Rows

#### Example 1: Successful Conversion

```json
{
  "result_id": "650e8400-e29b-41d4-a716-446655440000",
  "lock_id": "550e8400-e29b-41d4-a716-446655440000",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0000",
  "planning_run_id": "2026-03-18T03:15:00Z",
  "processing_month": "2026-03",
  "statement_date": "2026-03-01",
  "ban": "10000001",
  "source_tar_uri": "gs://afp-input/monthly/2026-03/day-01.tar",
  "source_member_path": "batch001/10000001_20260301.afp",
  "destination_uri": "gs://afp-output-residential/invoices/2026-03/10000001_20260301.pdf",
  "worker_id": "worker-vm-01",
  "attempt_number": 1,
  "result_status": "SUCCESS",
  "failure_code": null,
  "failure_message": null,
  "converter_exit_code": 0,
  "output_bytes": 524288,
  "output_sha256": "sha256:abc123def456...",
  "started_at": "2026-03-18T12:15:00Z",
  "completed_at": "2026-03-18T12:15:30Z",
  "inserted_at": "2026-03-18T12:15:31Z"
}
```

#### Example 2: Failed Conversion

```json
{
  "result_id": "650e8400-e29b-41d4-a716-446655440001",
  "lock_id": "550e8400-e29b-41d4-a716-446655440000",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0000",
  "planning_run_id": "2026-03-18T03:15:00Z",
  "processing_month": "2026-03",
  "statement_date": "2026-03-01",
  "ban": "10000002",
  "source_tar_uri": "gs://afp-input/monthly/2026-03/day-01.tar",
  "source_member_path": "batch001/10000002_20260301.afp",
  "destination_uri": null,
  "worker_id": "worker-vm-01",
  "attempt_number": 1,
  "result_status": "FAILED",
  "failure_code": "CONVERTER_ERROR",
  "failure_message": "Converter exited with code 1: unsupported AFP version",
  "converter_exit_code": 1,
  "output_bytes": null,
  "output_sha256": null,
  "started_at": "2026-03-18T12:16:00Z",
  "completed_at": "2026-03-18T12:16:05Z",
  "inserted_at": "2026-03-18T12:16:06Z"
}
```

#### Example 3: Skipped Conversion

```json
{
  "result_id": "650e8400-e29b-41d4-a716-446655440002",
  "lock_id": "550e8400-e29b-41d4-a716-446655440001",
  "shard_key": "2026-03_2026-03-01_2026-03-03_chunk_0001",
  "planning_run_id": "2026-03-18T03:15:00Z",
  "processing_month": "2026-03",
  "statement_date": "2026-03-01",
  "ban": "10000003",
  "source_tar_uri": "gs://afp-input/monthly/2026-03/day-01.tar",
  "source_member_path": "batch001/10000003_20260301.afp",
  "destination_uri": "gs://afp-output-residential/invoices/2026-03/10000003_20260301.pdf",
  "worker_id": "worker-vm-02",
  "attempt_number": 2,
  "result_status": "SKIPPED",
  "failure_code": null,
  "failure_message": null,
  "converter_exit_code": null,
  "output_bytes": 524288,
  "output_sha256": "sha256:ghi789jkl012...",
  "started_at": "2026-03-18T13:00:00Z",
  "completed_at": "2026-03-18T13:00:02Z",
  "inserted_at": "2026-03-18T13:00:03Z"
}
```

## Reporting Views

### View 1: `vw_month_progress`

Purpose: Show total expected, successful, failed, skipped, and remaining conversions for each month.

```sql
CREATE OR REPLACE VIEW `project.afp_pipeline.vw_month_progress` AS
SELECT
  JSON_VALUE(w.metadata_json, '$.processing_month') AS processing_month,
  SUM(CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64)) AS expected_conversions,
  COUNTIF(r.result_status = 'SUCCESS') AS successful_conversions,
  COUNTIF(r.result_status = 'FAILED') AS failed_attempts,
  COUNTIF(r.result_status = 'SKIPPED') AS skipped_conversions,
  SUM(CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64)) - COUNTIF(r.result_status = 'SUCCESS') AS remaining_conversions,
  ROUND(SAFE_DIVIDE(COUNTIF(r.result_status = 'SUCCESS'), SUM(CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64))) * 100, 2) AS completion_pct
FROM `project.afp_pipeline.work_locks` w
LEFT JOIN `project.afp_pipeline.conversion_results` r
  ON w.lock_id = r.lock_id
GROUP BY 1
ORDER BY 1 DESC;
```

### View 2: `vw_chunk_progress`

Purpose: Show one line per chunk with expected count, successes, failures, current lock status, and retry count.

```sql
CREATE OR REPLACE VIEW `project.afp_pipeline.vw_chunk_progress` AS
SELECT
  w.shard_key,
  w.lock_id,
  JSON_VALUE(w.metadata_json, '$.processing_month') AS processing_month,
  CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64) AS expected_conversion_count,
  COUNTIF(r.result_status = 'SUCCESS') AS success_count,
  COUNTIF(r.result_status = 'FAILED') AS failed_count,
  CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64) - COUNTIF(r.result_status = 'SUCCESS') AS remaining_count,
  w.status AS lock_status,
  w.attempt_count
FROM `project.afp_pipeline.work_locks` w
LEFT JOIN `project.afp_pipeline.conversion_results` r
  ON w.lock_id = r.lock_id
GROUP BY w.shard_key, w.lock_id, w.metadata_json, w.status, w.attempt_count
ORDER BY w.priority DESC;
```

### View 3: `vw_worker_throughput`

Purpose: Show how much work each VM is completing.

```sql
CREATE OR REPLACE VIEW `project.afp_pipeline.vw_worker_throughput` AS
SELECT
  worker_id,
  processing_month,
  COUNTIF(result_status = 'SUCCESS') AS success_count,
  COUNTIF(result_status = 'FAILED') AS failed_count,
  ROUND(AVG(TIMESTAMP_DIFF(completed_at, started_at, SECOND)), 2) AS avg_duration_seconds,
  MAX(completed_at) AS last_success_at
FROM `project.afp_pipeline.conversion_results`
GROUP BY worker_id, processing_month
ORDER BY processing_month DESC, success_count DESC;
```

### View 4: `vw_stale_and_retried_chunks`

Purpose: Highlight operational trouble spots.

```sql
CREATE OR REPLACE VIEW `project.afp_pipeline.vw_stale_and_retried_chunks` AS
SELECT
  w.shard_key,
  w.lock_id,
  JSON_VALUE(w.metadata_json, '$.processing_month') AS processing_month,
  w.status,
  w.attempt_count,
  w.max_attempts,
  w.worker_id,
  w.lease_expires_at,
  CASE
    WHEN w.status = 'LEASED' AND w.lease_expires_at < CURRENT_TIMESTAMP() THEN 'STALE_LEASE'
    WHEN w.attempt_count >= w.max_attempts THEN 'MAX_ATTEMPTS_REACHED'
    WHEN w.attempt_count >= 2 THEN 'RETRIED'
    ELSE 'NORMAL'
  END AS issue_type,
  COUNTIF(r.result_status = 'FAILED') AS failed_result_count
FROM `project.afp_pipeline.work_locks` w
LEFT JOIN `project.afp_pipeline.conversion_results` r
  ON w.lock_id = r.lock_id
WHERE w.status IN ('LEASED', 'FAILED') OR w.attempt_count >= 2
GROUP BY w.shard_key, w.lock_id, w.metadata_json, w.status, w.attempt_count, w.max_attempts, w.worker_id, w.lease_expires_at
ORDER BY w.attempt_count DESC, w.lease_expires_at ASC;
```

## Acceptance Criteria

This schema specification is ready for implementation when:

- all required fields are defined with types and constraints
- nullable vs required is explicit
- partitioning and clustering recommendations are clear
- example rows demonstrate expected data
- reporting views answer key operational questions
- field meanings are unambiguous

## Recommended Implementation Order

1. Create the `work_locks` table with partitioning and clustering.
2. Create the `conversion_results` table with partitioning and clustering.
3. Implement the four recommended reporting views.
4. Test with sample data to validate view logic.
5. Document any additional views needed for specific operational queries.