# AFP-to-PDF Pipeline Architecture

## Purpose

This document defines the recommended v1 architecture for the AFP-to-PDF invoice backfill pipeline.

It is written as a developer handoff document for a team of two engineers delivering in five months. It assumes the BigQuery lock-table approach is required by project leadership, while still calling out where that choice is a compromise.

## Companion Documents

- [planner-and-chunking.md](planner-and-chunking.md): deterministic chunk planning, BAN-list manifest contract, seeding flow, and worker expectations
- [worker-processing.md](worker-processing.md): worker daemon responsibilities, processing flow, validations, and idempotency expectations
- [conversion-results.md](conversion-results.md): reporting table contract, statuses, validation rules, and progress views
- [diagrams/architecture_diagram.md](diagrams/architecture_diagram.md): high-level system architecture diagram
- [diagrams/work_lock_lifecycle_diagram.md](diagrams/work_lock_lifecycle_diagram.md): chunk leasing, worker processing, and stale-lease retry lifecycle
- [diagrams/worker_processing_diagram.md](diagrams/worker_processing_diagram.md): worker claim, manifest load, tar processing, validation, upload, and result recording flow

## Answers At A Glance

### What are good ways to distribute and schedule work to the 12 VMs?

Use a lease-based pull model:

- precompute deterministic chunks for the active month
- insert one `work_locks` row per chunk in BigQuery
- let each VM claim the next available chunk
- heartbeat while processing
- mark the chunk `DONE` or `FAILED`

This is better than static VM-to-day assignment because the workload will not be perfectly balanced.

### How should we architect, plan, and execute the project?

Build the system around four core flows:

1. ingest source tar files into GCS
2. run a Python planner that creates deterministic date-range chunks and BAN-list files
3. run a Python worker daemon on 12 Linux VMs that leases chunks from BigQuery
4. write append-only conversion results so progress and remaining work can be measured independently of lock status

### What architecture is recommended?

Recommended v1 architecture:

- GCS input bucket for `.tar` source files
- Python planner / chunk seeding job
- BigQuery `work_locks` table for coarse-grained leasing
- Python worker daemon on 12 Linux VMs
- vendor AFP-to-PDF converter invoked by the worker
- GCS output buckets / prefixes for PDFs
- versioned routing rules config for destination resolution
- BigQuery `conversion_results` table and reporting views for success, failure, and remaining counts

### Are there issues with the current ideas?

Yes, but they are manageable if we constrain the design:

- BigQuery is acceptable for coarse lock leasing, but it is not an ideal hot coordination database.
- SSH is acceptable for administration and break-glass support, but it should not be the orchestrator.
- Shell is acceptable for bootstrap and thin wrappers, but not as the primary workflow engine.
- dynamically choosing "any N BANs" at runtime is risky; every chunk must point to a precomputed BAN-list file.

### What should be shell scripting vs Python?

Python should own orchestration, chunking, locking, validation, retries, and reporting.

Shell should only own:

- VM bootstrap
- environment setup
- thin wrappers
- invoking the external converter binary
- packaging and deployment hooks

## Architecture Goals

The design should optimize for:

- predictable delivery in five months
- clear ownership for a two-developer team
- safe restart and recovery after VM failures
- deterministic chunk membership
- measurable progress by month, chunk, VM, and conversion result
- straightforward operational debugging

The design should not try to solve:

- autoscaling beyond the fixed 12-VM fleet
- multi-region active/active processing
- a generalized workflow platform
- fully real-time processing

## Recommended Architecture

### Core Components

#### 1. Input Bucket

Google Cloud Storage input bucket containing the source monthly `.tar` files.

Responsibilities:

- receive tar files for the active month
- preserve source artifacts for replay and audit
- expose a stable URI per source tar file

Examples:

- `gs://afp-input/monthly/2026-03/*.tar`
- `gs://afp-input/manifests/2026-03/...`

#### 2. Planner / Chunk Seeding Job

A Python job that prepares work for the workers.

Responsibilities:

- identify the current active month
- scan source tar inventory for that month
- derive deterministic date-range chunks
- cap chunk size using `target_ban_count`
- write exact BAN-list files to GCS
- insert `work_locks` rows into BigQuery
- assign chunk priority so the most recent month wins

Why it exists:

- workers should process work, not define work
- planning logic must guarantee that chunk membership is stable across retries and restarts

#### 3. BigQuery `work_locks` Table

BigQuery is the mandated coordination store for v1.

Responsibilities:

- hold one row per deterministic chunk
- allow workers to claim, heartbeat, complete, and fail work
- track lease ownership and retry state

Design rule:

- `work_locks` is a control plane table, not the system of record for detailed conversion results

#### 4. Worker Daemon On 12 Linux VMs

A Python worker process running continuously on each VM.

Responsibilities:

- claim the next eligible chunk
- download source tar file(s)
- download and validate the chunk BAN-list file
- extract and filter the relevant AFP files
- invoke the vendor converter
- route resulting PDFs to the correct output destination
- write per-item conversion results
- heartbeat the lock during processing
- complete or fail the chunk

Each worker should run as a long-lived service, ideally under `systemd`.

#### 5. Output Buckets / Prefixes

One or more GCS destinations for generated PDFs.

Responsibilities:

- store finalized PDFs
- preserve output object metadata for audit and reconciliation
- support routing by business rule

#### 6. Routing Rules Config

A versioned configuration file deployed with the workers.

Responsibilities:

- determine which bucket/prefix a PDF should be written to
- support routing based on known business dimensions
- keep routing logic out of shell scripts and out of hardcoded worker branches

Recommended form:

- YAML or JSON config loaded by Python on worker startup

Example rule dimensions:

- processing month
- line of business
- invoice type
- destination environment

#### 7. BigQuery `conversion_results` Table And Views

An append-only reporting table separate from `work_locks`.

Responsibilities:

- record one result per attempted conversion unit
- make it possible to count successful, failed, and remaining work
- support dashboards, reconciliation, and reruns

Views should expose:

- successful conversions
- failed conversions
- remaining conversions for active month
- chunk throughput by worker
- stale or retried chunk activity

## End-To-End Flow

### Happy Path

1. A month of tar files is placed in the input bucket.
2. The planner identifies the most recent uncompleted month as the active month.
3. The planner reads source inventory and creates deterministic date-range chunks.
4. For each chunk, the planner writes a BAN-list file to GCS and inserts a `work_locks` row in BigQuery.
5. A worker VM claims the highest-priority available chunk.
6. The worker downloads the chunk BAN-list file and relevant tar file(s).
7. The worker validates the tar, extracts or filters the needed AFP members, and converts them to PDFs.
8. The worker routes each PDF to the correct destination using the routing rules config.
9. The worker writes append-only conversion result rows.
10. The worker completes the chunk lock row.
11. Reporting views update counts for successful, failed, and remaining work.
12. When the active month is materially complete, the planner seeds the next earlier month.

## Work Distribution And Scheduling Strategy

### Scheduling Principles

- process the most recent month first
- move backward month by month
- treat "one month per day" as a throughput target, not a hard SLA
- keep one active month at the highest priority until it is materially complete
- only begin the next month when the active month is stable or near completion

### Chunking Model

Each chunk must include:

- `date_range_start`
- `date_range_end`
- `target_ban_count`
- `selected_ban_count`
- `chunk_index`
- `ban_list_uri`

Interpretation:

- the date range defines the billing-day window
- `target_ban_count` is the intended chunk cap
- `selected_ban_count` is the actual number of BANs assigned
- `chunk_index` uniquely orders chunks within the same date window
- `ban_list_uri` points to the exact, immutable BAN membership list

### Deterministic Chunking Rule

Workers must never choose "any 25,000 BANs" at claim time.

The planner must:

1. identify all BANs belonging to the chosen date window
2. sort them deterministically
3. split them into fixed-size chunks
4. write each chunk to a BAN-list file
5. insert one lock row per file

This prevents:

- overlap between workers
- inconsistent reruns
- accidental duplicate processing

### Chunk Volume Guidance

For 12 VMs, seed more chunks than workers.

Recommended starting point:

- 60 to 120 chunks per active month

Tune chunk size based on:

- average tar size
- AFP member counts
- converter speed
- destination upload latency
- observed chunk duration

### Priority Rules

Priority should be assigned so that:

- newer months outrank older months
- within the same month, earlier planned chunks outrank later chunks
- retried chunks can optionally receive a slight priority bump if they block month completion

Practical priority strategy:

- one priority band per month
- lower `chunk_index` wins inside the same month and date window

## Data Contracts

### `work_locks` Row Contract

Every row should identify:

- which month and date window it belongs to
- where the deterministic BAN list lives
- which source tar inventory it depends on
- how many attempts have occurred
- who currently owns the lease
- when the lease expires

Required semantics:

- one row equals one deterministic chunk
- a chunk is not complete until conversion results are written and validated
- a failed or expired chunk can be safely reclaimed

### BAN-List File Contract

Each BAN-list file stored in GCS should include, at minimum:

- processing month
- `date_range_start`
- `date_range_end`
- `chunk_index`
- exact BAN membership
- source tar URI(s) or source inventory reference
- expected AFP or invoice counts if known
- checksum/version metadata
- creation timestamp
- planner version

Recommended format:

- JSON for readability and operational debugging

Example shape:

```json
{
  "processing_month": "2026-03",
  "date_range_start": "2026-03-01",
  "date_range_end": "2026-03-03",
  "chunk_index": 0,
  "target_ban_count": 25000,
  "selected_ban_count": 24871,
  "source_tar_uris": [
    "gs://afp-input/monthly/2026-03/day-01.tar"
  ],
  "bans": [
    "10000001",
    "10000002"
  ],
  "checksum": "sha256:...",
  "planner_version": "v1"
}
```

### `conversion_results` Table Contract

This table should be append-only.

Recommended result grain:

- one row per attempted invoice conversion or per produced PDF

Each result row should capture:

- processing month
- chunk identifier
- BAN
- source tar URI
- source AFP member name or path
- destination PDF URI
- worker VM identifier
- attempt number
- result status (`SUCCESS`, `FAILED`, `SKIPPED`)
- failure code and message if any
- timing metadata
- checksum / size metadata where practical

### Progress Views And Metrics

The architecture should include reporting views or scheduled queries for:

- chunks pending / leased / done / failed
- conversions succeeded / failed
- remaining conversions for the active month
- worker throughput by VM
- chunks with stale leases
- chunks by retry count
- month completion percentage

Recommended remaining-work logic:

- planned work comes from chunk BAN lists and/or planner inventory
- completed work comes from successful `conversion_results`
- remaining work is computed from the difference, not from lock state alone

## Validations And Reliability Rules

### Input Validations

Before processing a chunk:

- tar can be opened
- tar is not empty
- AFP members are discoverable
- duplicate member names are detected and handled consistently
- invalid member names or unsupported files are logged and classified

### Planning Validations

The planner must verify:

- no overlapping BAN membership across chunk files
- no missing BANs within the planned set
- `selected_ban_count <= target_ban_count`
- chunk metadata matches the BAN-list file
- every chunk points to a real `ban_list_uri`
- source tar references exist

### Lease Validations

Workers must enforce:

- heartbeat interval shorter than lease expiry
- reclaim behavior after VM death
- capped retries using `max_attempts`
- no completion without ownership of the current lease token

Recommended lease defaults:

- heartbeat every 3 to 5 minutes
- lease duration 10 to 15 minutes
- small jitter on heartbeat timing so all 12 VMs do not update at once

### Conversion Validations

For every output:

- converter exit code must indicate success
- output file must exist
- output size must be greater than zero
- output must have a valid PDF signature header
- destination upload must succeed
- destination URI must match routing rules

### Completion Validations

Before completing a chunk:

- conversion results are written
- actual converted count matches expected chunk accounting within defined rules
- failures are recorded explicitly, not inferred from missing output

### Idempotency Rules

Reruns must be safe.

The system must avoid:

- duplicate outputs with different names unless explicitly versioned
- silent overwrite without a defined policy
- ambiguous chunk membership on retry

Recommended v1 idempotency policy:

- destination object naming must be deterministic
- existing successful outputs should be checked before rewriting
- reclaiming a failed or expired chunk should skip already successful items where possible
- results table should record retries rather than mutating prior result rows

## Failure Scenarios And Handling

### VM Crash Mid-Chunk

Expected behavior:

- the worker stops heartbeating
- the lease expires
- another worker reclaims the chunk
- already completed outputs are not duplicated

### Stale Lease Reclaim

Expected behavior:

- expired chunk is eligible again
- reclaim increments attempt count
- reporting shows stale-lease activity for review

### Bad Tar Or Corrupted AFP

Expected behavior:

- worker records structured failure results
- chunk fails with a reason code
- retries occur only up to `max_attempts`
- repeated data-quality failures are surfaced to operations

### Partial Chunk Success

Expected behavior:

- successful items are recorded
- failed items are recorded separately
- chunk can fail overall without losing success accounting
- retry logic should not require redoing known good work if avoidable

### Destination Write Failure

Expected behavior:

- the failed write is recorded explicitly
- the chunk remains incomplete
- retry behavior depends on whether the upload error is transient or terminal

### BigQuery Transient Errors

Expected behavior:

- planner and workers use bounded retries with backoff
- lock updates are retried carefully
- conversion results are not double-written without an idempotency check

## Current Ideas: What Is Okay Vs Risky

### Okay

- using 12 fixed Linux VMs
- using GCS input tar files and GCS output PDFs
- using a BigQuery lock table if chunk updates are coarse and controlled
- using a month-by-month backlog with most recent month first
- using shell for bootstrap and converter invocation

### Risky

- using SSH as an orchestrator instead of a worker daemon
- using shell as the primary workflow engine
- using BigQuery as a high-churn fine-grained lock database
- assigning static work per VM instead of dynamic claim/lease
- allowing workers to choose BANs dynamically at runtime
- relying on lock rows alone for progress reporting

## Shell Vs Python Decision

### Python Owns

- planner and deterministic chunk seeding
- GCS access
- BigQuery access
- worker lease loop
- validations
- retries and backoff
- routing rule evaluation
- results reporting
- progress calculations and admin scripts beyond the simplest wrappers

### Shell Owns

- VM bootstrap / startup scripts
- thin wrapper scripts
- invoking the vendor converter binary
- packaging and deployment hooks
- simple operational helpers

### Decision

Do not use shell as the primary orchestrator for this project.

Reason:

- lease ownership and retry logic are stateful
- progress accounting needs structured data
- validations are easier and safer in Python
- shell becomes brittle quickly when coordinating long-running distributed work

## Technologies To Use

### Required

- Python 3.x on Linux VMs
- Bash for thin wrappers and startup
- Google Cloud Storage
- Google BigQuery
- Terraform for infrastructure
- vendor AFP-to-PDF converter binary
- `systemd` for worker process management

### Recommended Python Libraries

- `google-cloud-storage`
- `google-cloud-bigquery`
- `pydantic` or dataclass-based config/validation layer
- `tenacity` or equivalent retry helper if the team prefers a library over custom retry code

These are optional quality-of-life choices, not hard requirements.

## Operational Observability

The pipeline should surface, at minimum:

- current active month
- total planned chunks for that month
- chunks completed / remaining
- successful conversions / failed conversions / remaining conversions
- worker heartbeat freshness by VM
- average chunk duration
- average conversion throughput per VM
- retry distribution and stuck chunk counts

Recommended operational surfaces:

- BigQuery views
- simple scheduled reports
- VM logs in Cloud Logging if available
- daily reconciliation summary for the active month

## Delivery Plan And Execution Strategy

### Month 1

- finalize the architecture and contracts
- stand up buckets, BigQuery dataset, and VM access
- prove converter invocation on one VM
- define BAN-list file schema and routing config schema

### Month 2

- implement planner and deterministic chunk seeding
- finalize lock-table claim / heartbeat / complete / fail flow
- build the basic Python worker daemon and `systemd` service

### Month 3

- integrate tar handling, AFP extraction, conversion, and output routing
- add result recording and core validations
- validate end-to-end processing for one month slice

### Month 4

- add retries, stale-lease recovery, and reporting views
- add runbooks and operational procedures
- perform end-to-end rehearsals on representative backfill volumes

### Month 5

- tune chunk size and throughput
- run failure drills
- harden error handling and idempotency
- validate the "month per day" target against real volumes
- complete production readiness review

### Recommended Staffing Split

Developer 1:

- planner
- BigQuery locking
- result tables and views
- reporting and reconciliation

Developer 2:

- worker daemon
- tar handling
- converter integration
- output routing and upload path

Shared:

- schema design
- validation rules
- end-to-end integration
- failure drills
- deployment and runbooks

## Alternatives And Tradeoffs

The chosen path is BigQuery lock-table coordination because that constraint is already set.

This is acceptable for v1 because:

- the fleet size is moderate
- the work is batch-oriented
- the lock model can be made coarse

It is still a compromise relative to:

- Cloud SQL
- Firestore
- queue-native task distribution

To keep BigQuery workable, the design depends on:

- coarse deterministic chunks
- low-frequency heartbeats
- more chunks than workers
- append-only results tracking outside the lock row

If the project later outgrows this model, the worker/planner separation should make it possible to swap the coordination layer without redesigning the full conversion pipeline.

## Acceptance Criteria For This Architecture

The architecture should be considered complete enough for implementation when:

- work distribution is deterministic
- the worker loop is clearly defined
- progress can be measured independently of lock rows
- failure recovery is explicit
- shell and Python responsibilities are intentionally split
- the five-month plan is realistic for two developers
- the most recent month first strategy is operationally clear

## Recommended Next Implementation Steps

1. Add the `conversion_results` schema and initial reporting views.
2. Implement the planner that writes BAN-list files and seeds `work_locks`.
3. Implement the Python worker daemon and `systemd` service.
4. Define the routing rules config and destination naming convention.
5. Run one end-to-end month slice rehearsal before scaling out to the full backlog.
