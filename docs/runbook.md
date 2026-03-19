# AFP-to-PDF Pipeline Runbook

## Purpose

This runbook provides operational procedures for day-to-day management of the AFP-to-PDF pipeline, including how to start/stop workers, requeue failed chunks, inspect progress, handle stale leases, replay a month, and troubleshoot common issues.

This is the go-to guide for operators and on-call engineers.

## Scope

This document covers:

- starting and stopping workers
- monitoring pipeline health
- inspecting progress and remaining work
- handling failed chunks
- recovering from stale leases
- replaying or reprocessing a month
- common troubleshooting procedures
- log locations and what to check first

This document does not cover:

- initial deployment and infrastructure setup (see deployment guide)
- code changes or development workflows
- detailed architecture explanations (see architecture.md)

## Quick Reference

### Common Commands

```bash
# Check worker status on a VM
sudo systemctl status afp-worker

# View worker logs
sudo journalctl -u afp-worker -f

# Restart a worker
sudo systemctl restart afp-worker

# Stop a worker
sudo systemctl stop afp-worker

# Start a worker
sudo systemctl start afp-worker
```

### Key BigQuery Queries

See [Monitoring Queries](#monitoring-queries) section below.

## System Overview

### Components

- **12 Worker VMs**: Linux VMs running Python worker daemons under systemd
- **Planner Job**: Python job that creates chunks and seeds work_locks
- **BigQuery Tables**: `work_locks` and `conversion_results`
- **GCS Buckets**: Input bucket (tar files), manifest bucket (chunk definitions), output buckets (PDFs)

### Normal Operation Flow

1. Planner identifies active month and creates chunks
2. Workers claim chunks from `work_locks`
3. Workers process chunks and write results to `conversion_results`
4. Workers complete or fail chunks
5. Reporting views show progress

## Starting and Stopping Workers

### Starting All Workers

To start workers on all 12 VMs:

```bash
# SSH to each VM and run:
sudo systemctl start afp-worker

# Or use a deployment script if available:
./scripts/admin/start_all_workers.sh
```

### Stopping All Workers

To stop workers gracefully:

```bash
# SSH to each VM and run:
sudo systemctl stop afp-worker

# Or use a deployment script:
./scripts/admin/stop_all_workers.sh
```

**Important**: Workers will finish processing their current chunk before stopping. This may take 10-30 minutes depending on chunk size.

### Restarting A Single Worker

If a specific worker is stuck or needs to be restarted:

```bash
# SSH to the VM
ssh worker-vm-01

# Restart the worker
sudo systemctl restart afp-worker

# Check status
sudo systemctl status afp-worker

# Tail logs to verify restart
sudo journalctl -u afp-worker -f
```

### Checking Worker Status

To check if workers are running:

```bash
# On a specific VM
sudo systemctl status afp-worker

# Check all workers (if monitoring script exists)
./scripts/admin/check_worker_health.sh
```

Expected output for a healthy worker:

```
● afp-worker.service - AFP to PDF Worker Daemon
   Loaded: loaded (/etc/systemd/system/afp-worker.service; enabled)
   Active: active (running) since 2026-03-18 12:00:00 UTC; 2h 30min ago
   Main PID: 12345 (python3)
   ...
```

## Monitoring Pipeline Health

### Key Metrics To Monitor

1. **Active workers**: How many workers are running and claiming chunks
2. **Chunks pending**: How many chunks are available for claim
3. **Chunks leased**: How many chunks are currently being processed
4. **Chunks completed**: How many chunks have finished successfully
5. **Chunks failed**: How many chunks have failed
6. **Stale leases**: Chunks with expired leases that need reclaim
7. **Conversion success rate**: Percentage of successful conversions
8. **Worker throughput**: Conversions per hour per worker

### Monitoring Queries

#### Overall Progress By Month

```sql
SELECT * FROM `project.afp_pipeline.vw_month_progress`
ORDER BY processing_month DESC;
```

Expected columns:
- `processing_month`
- `expected_conversions`
- `successful_conversions`
- `failed_attempts`
- `skipped_conversions`
- `remaining_conversions`
- `completion_pct`

#### Chunk Status Summary

```sql
SELECT
  status,
  COUNT(*) AS chunk_count,
  SUM(selected_ban_count) AS total_bans
FROM `project.afp_pipeline.work_locks`
GROUP BY status
ORDER BY status;
```

#### Worker Throughput

```sql
SELECT * FROM `project.afp_pipeline.vw_worker_throughput`
WHERE processing_month = '2026-03'
ORDER BY success_count DESC;
```

#### Stale Leases

```sql
SELECT * FROM `project.afp_pipeline.vw_stale_and_retried_chunks`
WHERE issue_type = 'STALE_LEASE'
ORDER BY lease_expires_at ASC;
```

#### Failed Chunks

```sql
SELECT
  shard_key,
  status,
  attempt_count,
  max_attempts,
  worker_id,
  updated_at
FROM `project.afp_pipeline.work_locks`
WHERE status = 'FAILED'
ORDER BY updated_at DESC
LIMIT 50;
```

## Inspecting Progress

### How Much Work Remains?

```sql
SELECT
  processing_month,
  expected_conversions,
  successful_conversions,
  remaining_conversions,
  completion_pct
FROM `project.afp_pipeline.vw_month_progress`
WHERE processing_month = '2026-03';
```

### Which Chunks Are Still Pending?

```sql
SELECT
  shard_key,
  date_range_start,
  date_range_end,
  selected_ban_count,
  priority,
  created_at
FROM `project.afp_pipeline.work_locks`
WHERE status = 'PENDING'
ORDER BY priority DESC
LIMIT 100;
```

### Which Chunks Are Currently Being Processed?

```sql
SELECT
  shard_key,
  worker_id,
  lease_expires_at,
  TIMESTAMP_DIFF(lease_expires_at, CURRENT_TIMESTAMP(), MINUTE) AS minutes_until_expiry,
  attempt_count,
  updated_at
FROM `project.afp_pipeline.work_locks`
WHERE status = 'LEASED'
ORDER BY lease_expires_at ASC;
```

### What Is The Current Active Month?

```sql
SELECT
  JSON_VALUE(metadata_json, '$.processing_month') AS processing_month,
  COUNT(*) AS chunk_count,
  COUNTIF(status = 'DONE') AS completed_chunks,
  COUNTIF(status = 'PENDING') AS pending_chunks,
  COUNTIF(status = 'LEASED') AS leased_chunks,
  COUNTIF(status = 'FAILED') AS failed_chunks
FROM `project.afp_pipeline.work_locks`
GROUP BY 1
ORDER BY 1 DESC
LIMIT 5;
```

## Handling Failed Chunks

### Identifying Failed Chunks

```sql
SELECT
  shard_key,
  attempt_count,
  max_attempts,
  worker_id,
  updated_at,
  completed_at
FROM `project.afp_pipeline.work_locks`
WHERE status = 'FAILED'
ORDER BY updated_at DESC;
```

### Investigating Failure Reasons

```sql
SELECT
  failure_code,
  COUNT(*) AS failure_count,
  COUNT(DISTINCT shard_key) AS affected_chunks
FROM `project.afp_pipeline.conversion_results`
WHERE result_status = 'FAILED'
  AND processing_month = '2026-03'
GROUP BY failure_code
ORDER BY failure_count DESC;
```

### Viewing Detailed Failure Messages

```sql
SELECT
  shard_key,
  ban,
  source_member_path,
  failure_code,
  failure_message,
  completed_at
FROM `project.afp_pipeline.conversion_results`
WHERE result_status = 'FAILED'
  AND shard_key = '2026-03_2026-03-01_2026-03-03_chunk_0000'
ORDER BY completed_at DESC
LIMIT 100;
```

### Requeuing A Failed Chunk

To manually requeue a failed chunk for retry:

```sql
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  attempt_count = 0,
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE shard_key = '2026-03_2026-03-01_2026-03-03_chunk_0000'
  AND status = 'FAILED';
```

**Warning**: Only requeue chunks after investigating the root cause. Repeated failures may indicate data quality issues or configuration problems.

### Requeuing Multiple Failed Chunks

To requeue all failed chunks for a specific failure code:

```sql
-- First, identify the chunks
SELECT DISTINCT shard_key
FROM `project.afp_pipeline.conversion_results`
WHERE result_status = 'FAILED'
  AND failure_code = 'CONVERTER_ERROR'
  AND processing_month = '2026-03';

-- Then, requeue them (use with caution)
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  attempt_count = 0,
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE shard_key IN (
  SELECT DISTINCT shard_key
  FROM `project.afp_pipeline.conversion_results`
  WHERE result_status = 'FAILED'
    AND failure_code = 'CONVERTER_ERROR'
    AND processing_month = '2026-03'
)
AND status = 'FAILED';
```

## Handling Stale Leases

### Identifying Stale Leases

Stale leases occur when a worker crashes or loses connectivity without completing a chunk.

```sql
SELECT
  shard_key,
  worker_id,
  lease_expires_at,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), lease_expires_at, MINUTE) AS minutes_stale,
  attempt_count,
  updated_at
FROM `project.afp_pipeline.work_locks`
WHERE status = 'LEASED'
  AND lease_expires_at < CURRENT_TIMESTAMP()
ORDER BY lease_expires_at ASC;
```

### Automatic Stale Lease Recovery

**Normal behavior**: Workers automatically reclaim stale leases. No manual intervention is needed.

When a worker queries for available chunks, it includes chunks with expired leases. The worker will reclaim the chunk, increment the attempt count, and process it.

### Manual Stale Lease Recovery

If stale leases are not being reclaimed automatically (e.g., all workers are stopped):

```sql
-- Reset stale leases to PENDING
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE status = 'LEASED'
  AND lease_expires_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE);
```

**Note**: Only do this if workers are stopped or if you've confirmed the lease is truly stale.

## Replaying or Reprocessing A Month

### When To Replay

Replay a month when:

- source data was corrected or updated
- routing rules changed and outputs need to be regenerated
- a systemic failure affected many chunks
- testing or validation requires a full rerun

### Replay Procedure

#### Option 1: Requeue All Chunks For A Month

```sql
-- Reset all chunks for a month to PENDING
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  attempt_count = 0,
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  completed_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE JSON_VALUE(metadata_json, '$.processing_month') = '2026-03';
```

**Warning**: This will reprocess all chunks, including successful ones. Workers will skip already successful items if idempotency logic is enabled.

#### Option 2: Requeue Only Failed Chunks

```sql
-- Reset only failed chunks for a month
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  attempt_count = 0,
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE JSON_VALUE(metadata_json, '$.processing_month') = '2026-03'
  AND status = 'FAILED';
```

#### Option 3: Full Replanning

If the source data or chunking logic changed:

1. Stop all workers
2. Delete existing `work_locks` rows for the month
3. Delete existing manifests from GCS (optional, for cleanup)
4. Run the planner job to recreate chunks
5. Start workers

```sql
-- Delete work_locks rows for a month
DELETE FROM `project.afp_pipeline.work_locks`
WHERE JSON_VALUE(metadata_json, '$.processing_month') = '2026-03';
```

```bash
# Delete manifests (optional)
gsutil -m rm -r gs://afp-input/manifests/2026-03/

# Run planner
python3 /opt/afp-pipeline/planner/run_planner.py --month 2026-03

# Start workers
./scripts/admin/start_all_workers.sh
```

## Troubleshooting Common Issues

### Issue: Workers Are Not Claiming Chunks

**Symptoms**:
- Workers are running but not processing chunks
- No chunks in `LEASED` status
- Worker logs show "no available chunks"

**Possible Causes**:
1. No chunks in `PENDING` status
2. All chunks are `DONE` or `FAILED`
3. Worker query is not finding eligible chunks

**Resolution**:

```sql
-- Check chunk status distribution
SELECT status, COUNT(*) FROM `project.afp_pipeline.work_locks` GROUP BY status;

-- Check if there are pending chunks
SELECT COUNT(*) FROM `project.afp_pipeline.work_locks` WHERE status = 'PENDING';

-- If no pending chunks, check if month is complete
SELECT * FROM `project.afp_pipeline.vw_month_progress`;
```

If the month is complete, the planner needs to seed the next month.

### Issue: Worker Keeps Failing The Same Chunk

**Symptoms**:
- A chunk has `attempt_count >= 2`
- Same failure code appears repeatedly
- Chunk is stuck in retry loop

**Resolution**:

```sql
-- Identify the problematic chunk
SELECT
  shard_key,
  attempt_count,
  status,
  worker_id
FROM `project.afp_pipeline.work_locks`
WHERE attempt_count >= 2
ORDER BY attempt_count DESC;

-- Check failure details
SELECT
  failure_code,
  failure_message,
  COUNT(*) AS occurrence_count
FROM `project.afp_pipeline.conversion_results`
WHERE shard_key = '<problematic-shard-key>'
  AND result_status = 'FAILED'
GROUP BY failure_code, failure_message;
```

**Common Failure Codes**:

- `BAD_TAR`: Source tar is corrupt. Check source data.
- `BAD_AFP`: AFP member is corrupt or unsupported. Check converter compatibility.
- `CONVERTER_ERROR`: Converter binary failed. Check converter logs and version.
- `UPLOAD_FAILED`: GCS upload failed. Check network and permissions.
- `NO_ROUTING_RULE`: No routing rule matched. Check routing config.

**Actions**:

1. Investigate root cause based on failure code
2. Fix underlying issue (data, config, permissions)
3. Requeue the chunk or mark as permanently failed

### Issue: High Failure Rate

**Symptoms**:
- Many chunks in `FAILED` status
- High percentage of `FAILED` results in `conversion_results`

**Resolution**:

```sql
-- Check failure distribution
SELECT
  failure_code,
  COUNT(*) AS failure_count,
  COUNT(DISTINCT shard_key) AS affected_chunks
FROM `project.afp_pipeline.conversion_results`
WHERE result_status = 'FAILED'
  AND processing_month = '2026-03'
GROUP BY failure_code
ORDER BY failure_count DESC;
```

**Common Causes**:

- **CONVERTER_ERROR**: Converter version incompatibility or bug
- **BAD_AFP**: Source data quality issues
- **UPLOAD_FAILED**: Network or permissions issues
- **NO_ROUTING_RULE**: Routing config missing rules for new data

**Actions**:

1. Address the most common failure code first
2. Fix configuration, permissions, or data quality
3. Requeue affected chunks after fix

### Issue: Worker Logs Show Errors

**Symptoms**:
- Worker logs contain ERROR or CRITICAL messages
- Worker is running but not processing chunks

**Resolution**:

```bash
# View recent worker logs
sudo journalctl -u afp-worker -n 500

# Follow worker logs in real-time
sudo journalctl -u afp-worker -f

# Search for errors
sudo journalctl -u afp-worker | grep -i error

# Search for specific chunk
sudo journalctl -u afp-worker | grep "chunk_0000"
```

**Common Log Errors**:

- `Failed to claim chunk`: BigQuery connection issue or no available chunks
- `Failed to download manifest`: GCS permissions or manifest missing
- `Failed to download tar`: GCS permissions or tar missing
- `Converter exited with code 1`: Converter error, check converter logs
- `Failed to upload PDF`: GCS permissions or network issue
- `Failed to write conversion_results`: BigQuery permissions or schema mismatch

### Issue: Slow Progress

**Symptoms**:
- Chunks are completing but slower than expected
- Workers are processing but throughput is low

**Resolution**:

```sql
-- Check worker throughput
SELECT
  worker_id,
  success_count,
  avg_duration_seconds,
  last_success_at
FROM `project.afp_pipeline.vw_worker_throughput`
WHERE processing_month = '2026-03'
ORDER BY avg_duration_seconds DESC;

-- Check chunk duration distribution
SELECT
  shard_key,
  worker_id,
  TIMESTAMP_DIFF(completed_at, updated_at, MINUTE) AS duration_minutes
FROM `project.afp_pipeline.work_locks`
WHERE status = 'DONE'
  AND JSON_VALUE(metadata_json, '$.processing_month') = '2026-03'
ORDER BY duration_minutes DESC
LIMIT 50;
```

**Possible Causes**:

1. Large chunk size (too many BANs per chunk)
2. Slow converter performance
3. Network latency for GCS operations
4. VM resource constraints (CPU, memory, disk)

**Actions**:

1. Check VM resource utilization (CPU, memory, disk I/O)
2. Consider reducing `target_ban_count` for future months
3. Investigate converter performance
4. Check network latency to GCS

### Issue: Planner Not Seeding New Month

**Symptoms**:
- Current month is complete but next month not started
- No chunks for the next month in `work_locks`

**Resolution**:

```bash
# Check planner logs
sudo journalctl -u afp-planner -n 500

# Manually trigger planner
python3 /opt/afp-pipeline/planner/run_planner.py --month 2026-02
```

**Common Causes**:

- Planner not scheduled or not running
- Planner logic not detecting month completion
- Source data for next month not available

## Log Locations

### Worker Logs

```bash
# systemd journal (recommended)
sudo journalctl -u afp-worker -f

# If file-based logging is configured
tail -f /var/log/afp-pipeline/worker.log
```

### Planner Logs

```bash
# systemd journal
sudo journalctl -u afp-planner -f

# If file-based logging is configured
tail -f /var/log/afp-pipeline/planner.log
```

### What To Check First

When investigating an issue:

1. **Worker status**: `sudo systemctl status afp-worker`
2. **Recent worker logs**: `sudo journalctl -u afp-worker -n 100`
3. **Chunk status distribution**: Query `work_locks` by status
4. **Recent failures**: Query `conversion_results` for `FAILED` status
5. **Stale leases**: Query `vw_stale_and_retried_chunks`
6. **Worker throughput**: Query `vw_worker_throughput`

## Emergency Procedures

### Emergency Stop

To stop all processing immediately:

```bash
# Stop all workers
./scripts/admin/stop_all_workers.sh

# Or manually on each VM
sudo systemctl stop afp-worker
```

### Emergency Restart

To restart the entire pipeline:

```bash
# Stop all workers
./scripts/admin/stop_all_workers.sh

# Wait for workers to finish current chunks (check work_locks for LEASED status)

# Start all workers
./scripts/admin/start_all_workers.sh
```

### Data Corruption Recovery

If `work_locks` or `conversion_results` are corrupted:

1. Stop all workers
2. Backup current tables
3. Restore from backup or recreate from manifests
4. Restart workers

**Note**: This should be rare. Consult with the development team before attempting.

## Maintenance Windows

### Planned Maintenance

For planned maintenance (e.g., VM updates, configuration changes):

1. Stop all workers gracefully
2. Wait for all `LEASED` chunks to complete or expire
3. Perform maintenance
4. Restart workers
5. Verify workers are claiming chunks

### Rolling Maintenance

For rolling maintenance (one VM at a time):

1. Stop worker on one VM
2. Wait for its chunk to complete or expire
3. Perform maintenance on that VM
4. Restart worker on that VM
5. Verify it's claiming chunks
6. Repeat for next VM

## Escalation

### When To Escalate

Escalate to the development team when:

- repeated chunk failures with unknown failure codes
- systemic issues affecting multiple workers
- data corruption or schema mismatches
- performance degradation with no clear cause
- planner logic issues or chunking problems

### What Information To Provide

When escalating, include:

- description of the issue
- affected month(s) and chunk(s)
- relevant BigQuery queries and results
- worker logs showing errors
- timeline of when the issue started
- steps already taken to troubleshoot

## Related Documents

- [`architecture.md`](architecture.md): Overall system architecture
- [`worker-processing.md`](worker-processing.md): Worker processing flow
- [`planner-and-chunking.md`](planner-and-chunking.md): Planner design
- [`bigquery-schema.md`](bigquery-schema.md): Table schemas and views
- [`diagrams/failure_retry_diagram.md`](diagrams/failure_retry_diagram.md): Failure and retry flow