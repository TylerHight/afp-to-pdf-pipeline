# Conversion Results And Progress Reporting

## Purpose

This document defines the `conversion_results` reporting table, result statuses, validation rules, and progress views required to answer the operational questions the team cares about:

- how many conversions succeeded
- how many failed
- how many remain
- which VM processed what
- where retries and stale leases are happening

The key design rule is that progress reporting must not rely on `work_locks` state alone.

## Why A Separate Results Table

`work_locks` is a coarse control-plane table.

It can tell us:

- what chunks exist
- what state a chunk is in
- who owns the current lease

It cannot by itself answer:

- which invoice conversions inside a chunk succeeded
- which specific items failed
- how many outputs were already produced before a retry
- how many conversion units remain for the active month

For that reason, v1 should use a separate append-only `conversion_results` table.

## Grain

Recommended grain:

- one row per attempted conversion unit

For v1, a conversion unit should correspond to one expected output PDF or one source AFP member that should produce one PDF.

This makes progress measurable even when:

- a chunk partially succeeds
- a VM crashes mid-chunk
- a chunk is retried

## Table Schema

Recommended BigQuery table name:

- `conversion_results`

Recommended fields:

- `result_id` `STRING`
- `lock_id` `STRING`
- `shard_key` `STRING`
- `planning_run_id` `STRING`
- `processing_month` `STRING`
- `statement_date` `DATE`
- `ban` `STRING`
- `source_tar_uri` `STRING`
- `source_member_path` `STRING`
- `destination_uri` `STRING`
- `worker_id` `STRING`
- `attempt_number` `INT64`
- `result_status` `STRING`
- `failure_code` `STRING`
- `failure_message` `STRING`
- `converter_exit_code` `INT64`
- `output_bytes` `INT64`
- `output_sha256` `STRING`
- `started_at` `TIMESTAMP`
- `completed_at` `TIMESTAMP`
- `inserted_at` `TIMESTAMP`

### Field Notes

- `result_id` should be unique per result row.
- `lock_id` and `shard_key` tie the result back to the chunk.
- `processing_month` should use a stable `YYYY-MM` string for easier reporting.
- `attempt_number` should increase on retry.
- `result_status` should be controlled and finite.
- `destination_uri` should be present on success and may be null on failure.

## Result Statuses

Recommended statuses:

- `SUCCESS`
- `FAILED`
- `SKIPPED`

Status meanings:

- `SUCCESS`: the PDF was produced and stored successfully.
- `FAILED`: the item was attempted and failed.
- `SKIPPED`: the worker intentionally did not reconvert because a valid successful output already existed and idempotency rules allowed reuse.

Avoid ambiguous statuses like `DONE` or `ERROR` at the result level.

## Partitioning And Clustering

Recommended BigQuery settings:

- partition by `DATE(inserted_at)` or `DATE(completed_at)`
- cluster by `processing_month`, `result_status`, `worker_id`, `shard_key`

Why:

- reporting will usually filter by month and status
- operational queries often group by worker or chunk

## Write Rules

### Append-Only

Do not update prior result rows in place.

Instead:

- write a new row for each new attempt
- preserve the audit trail across retries

### Required Write Timing

Workers must write result rows before they complete the chunk lock.

This ensures:

- chunk completion and progress reporting stay aligned
- partial success is preserved even if the worker fails afterward

### Idempotency Guidance

Workers should use a deterministic natural key for pre-write duplicate checks when practical.

Recommended natural key components:

- `processing_month`
- `ban`
- `source_tar_uri`
- `source_member_path`
- `destination_uri`
- `attempt_number`

The worker may still generate a synthetic `result_id`.

## Validation Rules

### On Success

A `SUCCESS` row should only be written if:

- converter exit code indicates success
- destination upload succeeded
- output exists at the expected destination
- output size is greater than zero
- output has a valid PDF signature

### On Failure

A `FAILED` row should include:

- a stable `failure_code`
- a human-readable `failure_message`
- enough source identity to retry or investigate

Recommended v1 failure codes:

- `BAD_TAR`
- `BAD_AFP`
- `CONVERTER_ERROR`
- `OUTPUT_VALIDATION_FAILED`
- `UPLOAD_FAILED`
- `MANIFEST_ERROR`
- `LEASE_LOST`
- `UNKNOWN`

### On Skip

A `SKIPPED` row should only be used when:

- a valid successful output already exists
- the worker intentionally reuses it
- the skip is consistent with the documented idempotency policy

## Progress Logic

Progress should be computed from:

- planned work from chunk manifests and planner metadata
- observed work from `conversion_results`

### Planned Counts

Use planner data as the source of truth for expected work.

Recommended source:

- `work_locks.metadata_json.expected_conversion_count`
- or manifest-level planning summary derived from the same value

### Successful Counts

Successful counts come from:

- count of `SUCCESS` rows

### Remaining Counts

Recommended definition:

```text
remaining = expected_conversion_count_total - successful_conversion_count
```

Do not define remaining as:

- number of non-`DONE` locks
- number of `FAILED` locks

Those are useful operational signals, but not accurate progress metrics by themselves.

## Recommended Views

### 1. `vw_month_progress`

Purpose:

- show total expected, successful, failed, skipped, and remaining for each month

Should include:

- `processing_month`
- `expected_conversions`
- `successful_conversions`
- `failed_attempts`
- `skipped_conversions`
- `remaining_conversions`
- `completion_pct`

### 2. `vw_chunk_progress`

Purpose:

- show one line per chunk with expected count, successes, failures, current lock status, and retry count

Should include:

- `shard_key`
- `lock_id`
- `processing_month`
- `expected_conversion_count`
- `success_count`
- `failed_count`
- `remaining_count`
- `lock_status`
- `attempt_count`

### 3. `vw_worker_throughput`

Purpose:

- show how much work each VM is completing

Should include:

- `worker_id`
- `processing_month`
- `success_count`
- `failed_count`
- `avg_duration_seconds`
- `last_success_at`

### 4. `vw_stale_and_retried_chunks`

Purpose:

- highlight operational trouble spots

Should include:

- chunks with expired leases
- chunks above retry threshold
- chunks with repeated `FAILED` results

## Example Queries

### Month Progress

```sql
SELECT
  JSON_VALUE(w.metadata_json, '$.processing_month') AS processing_month,
  SUM(CAST(JSON_VALUE(w.metadata_json, '$.expected_conversion_count') AS INT64)) AS expected_conversions,
  COUNTIF(r.result_status = 'SUCCESS') AS successful_conversions,
  COUNTIF(r.result_status = 'FAILED') AS failed_attempts,
  COUNTIF(r.result_status = 'SKIPPED') AS skipped_conversions
FROM `project.dataset.work_locks` w
LEFT JOIN `project.dataset.conversion_results` r
  ON w.lock_id = r.lock_id
GROUP BY 1
ORDER BY 1 DESC;
```

### Worker Throughput

```sql
SELECT
  worker_id,
  processing_month,
  COUNTIF(result_status = 'SUCCESS') AS success_count,
  COUNTIF(result_status = 'FAILED') AS failed_count
FROM `project.dataset.conversion_results`
GROUP BY 1, 2
ORDER BY processing_month DESC, success_count DESC;
```

## Failure Handling

### Partial Chunk Failure

If half of a chunk succeeds and half fails:

- write `SUCCESS` rows for the successful items
- write `FAILED` rows for the failed items
- fail the chunk lock row if the chunk as a whole is incomplete

This preserves accurate progress and makes retries safer.

### VM Crash Mid-Chunk

If the VM crashes after writing some result rows:

- the lease should expire
- another worker can reclaim the chunk
- the new worker should check prior successful outputs and/or prior `SUCCESS` rows to avoid unnecessary rework

### Repeated Failures

Repeated failures should be visible through:

- failure code frequency
- repeated failures per source member
- chunks with multiple failed attempts but no successes

## Operational Reporting Questions This Design Answers

With this table and the recommended views, the team can answer:

- How many PDFs have been produced for the active month?
- How many remain?
- Which VM is fastest or stuck?
- Which chunks are failing repeatedly?
- Which source inputs fail most often?
- Are we on pace for the month-per-day target?

## Acceptance Criteria

This design is ready for implementation when:

- every worker write path can emit a structured result row
- every chunk can be tied back to its result rows through `lock_id` and `shard_key`
- month progress can be computed without depending on lock state alone
- partial success is represented correctly
- retries do not erase prior attempt history
