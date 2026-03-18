# Planner And Chunking Design

## Purpose

This document defines the planner job, deterministic chunking rules, BAN-list manifest contract, and the worker-facing expectations for chunk execution.

It exists to remove ambiguity from the most failure-sensitive part of the design: deciding exactly what a worker owns when it claims a chunk.

## Scope

This document covers:

- how the planner chooses the active month
- how tar inventory becomes deterministic chunks
- how BAN-list manifests are written
- how `work_locks` rows are seeded
- what the worker can assume when it claims a chunk

This document does not cover:

- vendor converter implementation details
- destination PDF naming internals
- BigQuery reporting views beyond the fields required for chunk accounting

## Planner Responsibilities

The planner is a Python job, not a shell script.

Responsibilities:

- determine the current active month
- enumerate source tar files for that month
- read enough source metadata to build chunk membership deterministically
- group work into date-range chunks
- cap chunk size using `target_ban_count`
- calculate chunk priority
- write one manifest file per chunk to GCS
- insert one `work_locks` row per chunk
- avoid duplicate chunk creation on repeated planner runs

Recommended runtime model:

- run the planner on one designated host or scheduled job
- trigger it on a timer or on operator command
- do not run planners concurrently unless leader election or a single-writer guard exists

## Active Month Selection

The planner should always prefer the most recent incomplete month.

Recommended rule:

1. list candidate processing months in descending order
2. choose the newest month with planned work that is not yet materially complete
3. do not seed older months ahead of newer months unless explicitly overridden by an operator

Materially complete can mean:

- all chunks are `DONE`, or
- remaining chunks are only terminal failures that require manual intervention

For v1, keep this simple:

- one active month at a time
- optional manual override for emergency backfill or replay

## Source Inventory Model

The planner must build a deterministic source inventory for the active month.

Minimum inventory attributes:

- `processing_month`
- `source_tar_uri`
- source tar checksum or generation if available
- AFP member path or member name
- BAN
- statement date or billing day
- any required routing dimensions already available from metadata

The planner may need a light metadata extraction step to derive these values from tar contents or sidecar data.

## Deterministic Chunking Rules

### Core Rule

Workers must never choose “any N BANs” at runtime.

The planner must assign exact membership before any lock row is created.

### Sorting Rule

The planner must sort candidate entries deterministically before chunking.

Recommended sort order:

1. `statement_date` ascending
2. `ban` ascending
3. `source_tar_uri` ascending
4. `afp_member_path` ascending

If any of these are missing, the planner must either derive them or fail planning for that source set.

### Chunk Boundaries

Each chunk is defined by:

- `date_range_start`
- `date_range_end`
- `target_ban_count`
- `selected_ban_count`
- `chunk_index`
- manifest location in GCS

Recommended v1 rule:

- keep all entries in a chunk within the same date-range window
- split by deterministic order until the chunk hits `target_ban_count`
- the final chunk in a window may be smaller than the target

### Date Windows

The PM requirement is to organize work by day-of-month range.

Recommended v1 policy:

- choose a date window size such as 1 to 3 days
- tune the window size using observed processing time
- keep the date window explicit in the chunk manifest and `work_locks` row

### Chunk Count Guidance

For 12 VMs, start with more chunks than workers.

Practical starting guidance:

- 60 to 120 chunks per active month

Adjust based on:

- average chunk duration
- mean and p95 conversion time
- upload latency
- converter throughput variability

## Manifest Contract

### Naming

Recommended manifest path:

```text
gs://afp-input/manifests/<processing-month>/<date-range-start>_<date-range-end>/chunk-<chunk-index>.json
```

Example:

```text
gs://afp-input/manifests/2026-03/2026-03-01_2026-03-03/chunk-0000.json
```

### Required Manifest Fields

Every manifest file must include:

- `contract_version`
- `planning_run_id`
- `processing_month`
- `date_range_start`
- `date_range_end`
- `chunk_index`
- `target_ban_count`
- `selected_ban_count`
- `expected_conversion_count`
- `source_tar_uris`
- `entries`
- `checksum`
- `planner_version`
- `created_at`

### Entry Contract

Each `entries` item should represent one deterministic conversion unit.

Minimum per-entry fields:

- `ban`
- `statement_date`
- `source_tar_uri`
- `afp_member_path`
- `source_member_checksum` if available
- optional routing dimensions already known at planning time

This is more useful than storing only BAN IDs because workers need to know the exact source item(s) that belong to the chunk.

### Example Manifest

```json
{
  "contract_version": "1",
  "planning_run_id": "2026-03-18T03:15:00Z",
  "processing_month": "2026-03",
  "date_range_start": "2026-03-01",
  "date_range_end": "2026-03-03",
  "chunk_index": 0,
  "target_ban_count": 25000,
  "selected_ban_count": 24871,
  "expected_conversion_count": 24871,
  "source_tar_uris": [
    "gs://afp-input/monthly/2026-03/day-01.tar"
  ],
  "entries": [
    {
      "ban": "10000001",
      "statement_date": "2026-03-01",
      "source_tar_uri": "gs://afp-input/monthly/2026-03/day-01.tar",
      "afp_member_path": "batch001/10000001_20260301.afp"
    }
  ],
  "checksum": "sha256:...",
  "planner_version": "v1",
  "created_at": "2026-03-18T03:15:00Z"
}
```

## `work_locks` Seeding Contract

Each manifest gets exactly one `work_locks` row.

Recommended field mapping:

- `shard_key` = `<processing-month>_<date-range-start>_<date-range-end>_chunk_<chunk-index>`
- `date_range_start` and `date_range_end` copied from manifest
- `target_ban_count` copied from manifest
- `selected_ban_count` copied from manifest
- `chunk_index` copied from manifest
- `ban_list_uri` = manifest GCS URI
- `priority` derived from month and chunk ordering
- `metadata_json` includes:
  - `processing_month`
  - `planning_run_id`
  - `expected_conversion_count`
  - `manifest_checksum`
  - `planner_version`
  - `routing_rules_version`

### Uniqueness Rule

The planner must treat `shard_key` as the logical unique identifier.

On rerun:

- if the same `shard_key` already exists and matches the manifest checksum, skip insert
- if the same `shard_key` exists but the manifest checksum differs, stop and require manual investigation

This prevents silent replanning drift.

## Priority Strategy

Use integer priorities so the worker can order work without extra joins.

Recommended rule:

```text
priority = (YYYYMM * 100000) - chunk_index
```

This gives:

- newer months higher priority than older months
- lower chunk index higher priority inside the same month

If retried chunks need a temporary boost, apply it carefully and only through a controlled operator action.

## Worker Expectations

When a worker claims a chunk, it may assume:

- the manifest is complete and immutable
- the manifest checksum matches planner expectations
- the entries list is the sole source of truth for chunk membership
- `expected_conversion_count` is the count to validate before completion

The worker must not:

- add new BANs or entries to the chunk
- remove entries unless they are filtered as already successful by defined idempotency logic
- rewrite the manifest file

## Planning Validations

The planner must validate before seeding:

- source tar exists
- source tar can be opened
- tar contains expected AFP members
- each planned entry appears in only one manifest
- no expected BANs are omitted from the active month inventory
- `selected_ban_count <= target_ban_count`
- `expected_conversion_count` matches the number of manifest entries
- manifest checksum is computed and stored

Recommended planner outputs for audit:

- planning run ID
- month planned
- chunk count
- total selected BAN count
- total expected conversion count
- manifest checksum summary

## Failure Handling

### Planner Rerun

If the planner reruns for the same active month:

- it should be safe and idempotent
- existing identical manifests should be reused
- duplicate `work_locks` rows should not be created

### Source Inventory Drift

If source tar inventory changes after planning:

- do not mutate existing manifests in place
- create a new planning run
- compare deltas explicitly
- decide whether to pause processing or seed additional chunks

### Bad Manifest

If a worker detects a malformed manifest:

- fail the chunk with a structured reason
- do not attempt dynamic reconstruction
- surface the issue to operations and developer review

## Recommended Implementation Order

1. Implement a source inventory reader for one active month.
2. Implement deterministic sorting and chunk splitting.
3. Implement manifest writing with checksum calculation.
4. Implement idempotent `work_locks` seeding.
5. Add validation and audit logging.
6. Prove worker consumption against one manifest file end to end.

## Acceptance Criteria

This design is ready for implementation when:

- two planner runs over the same source month produce identical manifests and shard keys
- every seeded `work_locks` row maps to exactly one manifest
- every manifest has explicit `expected_conversion_count`
- a worker can process a manifest without making any chunk-membership decisions
