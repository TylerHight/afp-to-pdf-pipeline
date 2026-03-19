# Worker Processing Design

## Purpose

This document defines what the worker daemon does after it claims a chunk from `work_locks`.

It is the execution-side companion to:

- [planner-and-chunking.md](planner-and-chunking.md)
- [conversion-results.md](conversion-results.md)
- [diagrams/work_lock_lifecycle_diagram.md](diagrams/work_lock_lifecycle_diagram.md)

The worker is responsible for processing work that has already been planned. It must not decide chunk membership at runtime.

## Worker Responsibilities

The worker daemon runs continuously on each of the 12 Linux VMs.

Responsibilities:

- claim the next available chunk
- renew the chunk lease while processing
- read the chunk definition file from GCS
- download the required tar file(s)
- extract or filter the required AFP members
- invoke the vendor AFP-to-PDF converter
- validate the generated PDF output
- route PDFs to the correct destination bucket/prefix
- write append-only `conversion_results` rows
- complete or fail the lock row

The worker should run under `systemd` as a long-lived service.

## Inputs

The worker consumes:

- `work_locks` rows from BigQuery
- chunk manifest JSON from GCS
- source tar files from the input bucket
- routing rules config deployed with the worker

## Outputs

The worker produces:

- PDFs written to output bucket(s)
- append-only `conversion_results` rows in BigQuery
- lock row state transitions in `work_locks`
- structured logs for local troubleshooting and centralized log collection

## Runtime Flow

### 1. Idle / Claim Loop

The worker repeatedly:

1. asks BigQuery for the next available chunk
2. attempts to claim it
3. if no chunk is available, waits and retries

Recommended behavior:

- add small jitter to polling intervals
- do not hot-loop when no work is available
- log chunk claim attempts with `lock_id`, `shard_key`, and VM identity

### 2. Validate Claim

After claim:

- confirm the returned row contains a valid `ban_list_uri`
- confirm the worker has the lease token needed for later heartbeat and completion
- load chunk metadata needed for logging and progress tracking

If the claim payload is malformed:

- fail the chunk with a structured error
- do not attempt to reconstruct missing metadata

### 3. Load Chunk Definition

The worker downloads the manifest JSON from the manifest location in GCS.

Validations:

- manifest exists
- manifest is readable
- checksum or integrity metadata matches expected values if available
- manifest contains required fields:
  - `processing_month`
  - `date_range_start`
  - `date_range_end`
  - `chunk_index`
  - `expected_conversion_count`
  - `source_tar_uris`
  - `entries`

The worker must treat the manifest as immutable.

## Source File Processing

### 4. Download Required Tar Files

The worker downloads only the tar files referenced by the claimed chunk.

Validations:

- source tar exists
- source tar download succeeds
- local file size is greater than zero

### 5. Extract / Filter Required AFP Members

The worker reads the tar file and filters to the exact entries listed in the manifest.

Validations:

- tar can be opened
- listed AFP members exist in the tar
- unsupported or duplicate members are handled consistently

The worker must not expand chunk membership beyond what the manifest defines.

### 6. Invoke Converter

For each conversion unit:

- prepare local working files
- invoke the vendor converter binary
- capture exit code, timing, and stderr/stdout where practical

The worker may process items sequentially in v1 unless parallel conversion inside a chunk is proven safe and necessary.

## Output Validation And Routing

### 7. Validate PDF Output

Before upload, validate:

- output file exists
- output size is greater than zero
- output starts with a valid PDF signature
- output file naming matches the intended destination rule

### 8. Route Output

The worker loads routing rules config at startup and uses it when uploading PDFs.

The routing rules config should determine:

- destination bucket
- destination prefix
- naming convention inputs

If no routing rule matches:

- record a failure result
- do not silently write to a fallback destination unless that fallback is explicitly defined

## Result Recording

### 9. Write `conversion_results`

For every attempted conversion unit, write one append-only result row.

On success, include:

- `lock_id`
- `shard_key`
- `processing_month`
- BAN
- source tar URI
- source member path
- destination URI
- worker ID
- attempt number
- status `SUCCESS`

On failure, include:

- the same identifiers
- status `FAILED`
- failure code
- failure message

If the worker skips a conversion because a valid output already exists and the idempotency policy allows reuse, write status `SKIPPED`.

### 10. Complete Or Fail Lock

Complete the chunk only after:

- results are written
- expected counts have been checked
- any chunk-level validation has passed

Fail the chunk when:

- manifest is invalid
- source tar is unreadable
- repeated conversion failures make the chunk incomplete
- destination writes fail in a way that leaves the chunk incomplete

## Heartbeat And Lease Management

The worker must heartbeat while processing.

Recommended defaults:

- heartbeat every 3 to 5 minutes
- lease duration 10 to 15 minutes
- use jitter to avoid synchronized updates across all 12 VMs

If the worker loses the lease:

- stop processing as soon as practical
- do not complete the chunk
- write failure or operational logs as needed

## Idempotency Rules

The worker must be safe to rerun.

Required behaviors:

- use deterministic destination naming
- check for existing successful outputs before rewriting when policy allows
- do not duplicate chunk membership
- preserve prior result rows across retries

Recommended v1 behavior:

- if a valid PDF already exists, write `SKIPPED` or reuse logic rather than blindly overwrite
- if a chunk is reclaimed, recheck prior successful outputs before converting again

## Error Handling

### Retryable Worker Conditions

Examples:

- temporary GCS read failure
- temporary upload failure
- transient BigQuery API issue

Use bounded retries with backoff.

### Non-Retryable Worker Conditions

Examples:

- malformed manifest
- corrupt tar with consistent failure
- unsupported AFP member
- missing required routing rule

These should be recorded explicitly and surfaced for review.

## Logging

Each worker should log, at minimum:

- worker ID / VM name
- claimed `lock_id`
- `shard_key`
- manifest URI
- source tar URI(s)
- result counts
- lease heartbeat activity
- completion or failure reason

## Recommended Implementation Structure

Suggested worker modules:

- lease client
- manifest loader
- tar reader / extractor
- converter wrapper
- pdf validator
- routing resolver
- results writer
- main worker loop

Shell should only be used for:

- service startup
- environment bootstrap
- thin wrapper around the external converter binary if needed

Python should own the workflow.

## Acceptance Criteria

This design is ready for implementation when:

- a worker can process a claimed chunk without deciding chunk membership
- manifest validation is explicit
- source tar handling and converter invocation are clearly separated
- output validation happens before success is recorded
- `conversion_results` are written before lock completion
- stale lease behavior and idempotency expectations are documented
