# Failure Handling and Recovery Guide

## Purpose

This document provides detailed procedures for handling and recovering from specific failure scenarios in the AFP-to-PDF pipeline.

It complements the [`runbook.md`](runbook.md) by providing deeper analysis of failure modes, root cause investigation, and recovery strategies.

## Scope

This document covers:

- VM crash scenarios and recovery
- bad tar file handling
- corrupt AFP member handling
- GCS upload failures
- repeated chunk failures
- stale lease recovery
- BigQuery transient errors
- network failures
- converter failures
- configuration errors

This document does not cover:

- routine operational procedures (see runbook.md)
- initial deployment (see deployment guide)
- architecture design decisions (see architecture.md)

## Failure Classification

### Transient Failures

**Definition**: Temporary failures that may succeed on retry without intervention.

**Examples**:
- Network timeouts
- GCS rate limiting
- BigQuery transient errors
- Temporary VM resource exhaustion

**Recovery Strategy**: Automatic retry with exponential backoff

### Persistent Failures

**Definition**: Failures that will not succeed on retry without fixing the underlying issue.

**Examples**:
- Corrupt source data
- Missing routing rules
- Invalid converter input
- Permissions errors

**Recovery Strategy**: Manual investigation and fix, then requeue

### Terminal Failures

**Definition**: Failures that cannot be recovered and require data or configuration changes.

**Examples**:
- Unsupported AFP version
- Missing source files
- Invalid manifest structure
- Schema mismatches

**Recovery Strategy**: Mark as permanently failed, investigate root cause, fix for future runs

## Failure Scenario 1: VM Crash

### Symptoms

- Worker VM is unresponsive
- SSH connection fails or times out
- Worker logs stop updating
- Chunks remain in `LEASED` status with expired leases
- No heartbeat updates for the worker

### Root Causes

1. **Out of Memory (OOM)**: Worker process killed by OS
2. **Disk Full**: Worker cannot write temporary files
3. **Kernel Panic**: OS-level crash
4. **Hardware Failure**: VM host failure
5. **Network Partition**: VM loses connectivity

### Investigation Steps

1. **Check VM Status**:
   ```bash
   gcloud compute instances describe afp-worker-01 --zone=us-central1-a
   ```

2. **Check Serial Console Logs**:
   ```bash
   gcloud compute instances get-serial-port-output afp-worker-01 --zone=us-central1-a
   ```

3. **Check Cloud Monitoring**:
   - CPU utilization before crash
   - Memory utilization before crash
   - Disk utilization before crash
   - Network traffic patterns

4. **Check Worker Logs** (if VM is accessible):
   ```bash
   ssh afp-worker-01
   sudo journalctl -u afp-worker -n 1000
   ```

### Recovery Procedure

#### If VM is Stopped

```bash
# Start the VM
gcloud compute instances start afp-worker-01 --zone=us-central1-a

# Wait for VM to boot
sleep 30

# Check worker service status
ssh afp-worker-01 'sudo systemctl status afp-worker'

# If service is not running, start it
ssh afp-worker-01 'sudo systemctl start afp-worker'

# Verify worker is claiming chunks
ssh afp-worker-01 'sudo journalctl -u afp-worker -f'
```

#### If VM is Unresponsive

```bash
# Reset the VM
gcloud compute instances reset afp-worker-01 --zone=us-central1-a

# Wait for VM to boot
sleep 60

# Check worker service status
ssh afp-worker-01 'sudo systemctl status afp-worker'
```

#### If VM Cannot Be Recovered

```bash
# Delete the failed VM
gcloud compute instances delete afp-worker-01 --zone=us-central1-a

# Recreate from template or Terraform
terraform apply -target=module.worker_vm[0]

# Or manually create a new VM with the same configuration
```

### Stale Lease Cleanup

After VM recovery, stale leases will be automatically reclaimed by other workers. No manual intervention is needed unless all workers are stopped.

If manual cleanup is required:

```sql
-- Check for stale leases from the crashed worker
SELECT
  shard_key,
  worker_id,
  lease_expires_at,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), lease_expires_at, MINUTE) AS minutes_stale
FROM `project.afp_pipeline.work_locks`
WHERE worker_id = 'afp-worker-01'
  AND status = 'LEASED'
  AND lease_expires_at < CURRENT_TIMESTAMP();

-- Reset stale leases to PENDING (only if workers are stopped)
UPDATE `project.afp_pipeline.work_locks`
SET
  status = 'PENDING',
  worker_id = NULL,
  lease_token = NULL,
  lease_expires_at = NULL,
  updated_at = CURRENT_TIMESTAMP()
WHERE worker_id = 'afp-worker-01'
  AND status = 'LEASED'
  AND lease_expires_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE);
```

### Prevention

1. **Monitor VM Resources**: Set up alerts for high CPU, memory, and disk usage
2. **Right-Size VMs**: Ensure VMs have sufficient resources for peak workload
3. **Implement Resource Limits**: Configure worker to limit memory and disk usage
4. **Regular Maintenance**: Apply OS updates during maintenance windows
5. **Use Preemptible VMs Carefully**: Understand preemption behavior and implement proper retry logic

## Failure Scenario 2: Bad Tar File

### Symptoms

- Worker logs show "Failed to open tar file" or "Tar file is corrupt"
- Multiple workers fail on the same chunk
- Failure code: `BAD_TAR`
- Chunk fails repeatedly with same error

### Root Causes

1. **Incomplete Upload**: Tar file upload was interrupted
2. **Corruption During Transfer**: Network corruption
3. **Corruption At Source**: Source system produced corrupt tar
4. **Wrong File Format**: File is not actually a tar file

### Investigation Steps

1. **Check Tar File Integrity**:
   ```bash
   # Download the tar file
   gsutil cp gs://afp-input/monthly/2026-03/day-01.tar /tmp/

   # Test tar file
   tar -tzf /tmp/day-01.tar > /dev/null
   echo $?  # Should be 0 if valid

   # Check file size
   ls -lh /tmp/day-01.tar

   # Check file type
   file /tmp/day-01.tar
   ```

2. **Check GCS Object Metadata**:
   ```bash
   gsutil stat gs://afp-input/monthly/2026-03/day-01.tar
   ```

3. **Check Upload Logs**: Review logs from source data provider

4. **Compare Checksum**: If source system provides checksums, compare

### Recovery Procedure

#### If Tar File Is Corrupt

1. **Request Re-Upload**:
   - Contact source data provider
   - Request re-upload of the corrupt tar file
   - Verify checksum after re-upload

2. **Mark Affected Chunks As Failed**:
   ```sql
   -- Find chunks using the corrupt tar
   SELECT
     shard_key,
     status,
     attempt_count
   FROM `project.afp_pipeline.work_locks`
   WHERE ban_list_uri LIKE '%2026-03-01%'
     AND status IN ('LEASED', 'PENDING', 'FAILED');

   -- Mark as failed with terminal status
   UPDATE `project.afp_pipeline.work_locks`
   SET
     status = 'FAILED',
     attempt_count = max_attempts,
     updated_at = CURRENT_TIMESTAMP(),
     completed_at = CURRENT_TIMESTAMP()
   WHERE ban_list_uri LIKE '%2026-03-01%'
     AND status IN ('LEASED', 'PENDING');
   ```

3. **After Re-Upload, Requeue Chunks**:
   ```sql
   -- Reset chunks to PENDING after tar is fixed
   UPDATE `project.afp_pipeline.work_locks`
   SET
     status = 'PENDING',
     attempt_count = 0,
     worker_id = NULL,
     lease_token = NULL,
     lease_expires_at = NULL,
     completed_at = NULL,
     updated_at = CURRENT_TIMESTAMP()
   WHERE ban_list_uri LIKE '%2026-03-01%'
     AND status = 'FAILED';
   ```

#### If Tar File Is Valid But Worker Cannot Read It

1. **Check Worker Permissions**:
   ```bash
   # Test GCS access from worker VM
   ssh afp-worker-01
   gsutil ls gs://afp-input/monthly/2026-03/day-01.tar
   gsutil cp gs://afp-input/monthly/2026-03/day-01.tar /tmp/test.tar
   ```

2. **Check Worker Disk Space**:
   ```bash
   ssh afp-worker-01
   df -h
   ```

3. **Check Worker Tar Utility**:
   ```bash
   ssh afp-worker-01
   which tar
   tar --version
   ```

### Prevention

1. **Validate Uploads**: Implement checksum validation on upload
2. **Retry Failed Uploads**: Source system should retry failed uploads
3. **Monitor Upload Success**: Alert on failed or incomplete uploads
4. **Test Tar Files**: Validate tar files before processing

## Failure Scenario 3: Corrupt AFP Member

### Symptoms

- Worker logs show "AFP member is corrupt" or "Unsupported AFP version"
- Converter exits with non-zero code
- Failure code: `BAD_AFP` or `CONVERTER_ERROR`
- Some items in chunk succeed, others fail

### Root Causes

1. **Unsupported AFP Version**: Converter doesn't support this AFP version
2. **Corrupt AFP Data**: AFP member is malformed
3. **Incomplete AFP Member**: AFP member was truncated
4. **Wrong File Type**: File is not actually AFP

### Investigation Steps

1. **Extract and Inspect AFP Member**:
   ```bash
   # Download tar and extract specific member
   gsutil cp gs://afp-input/monthly/2026-03/day-01.tar /tmp/
   tar -xzf /tmp/day-01.tar -C /tmp/ batch001/10000001_20260301.afp

   # Check file type
   file /tmp/batch001/10000001_20260301.afp

   # Check file size
   ls -lh /tmp/batch001/10000001_20260301.afp
   ```

2. **Test Converter Manually**:
   ```bash
   # Run converter on the AFP file
   /opt/afp-converter/bin/afp2pdf \
     --input /tmp/batch001/10000001_20260301.afp \
     --output /tmp/test.pdf

   # Check exit code
   echo $?

   # Check converter logs
   cat /opt/afp-converter/logs/converter.log
   ```

3. **Check Converter Version**:
   ```bash
   /opt/afp-converter/bin/afp2pdf --version
   ```

4. **Review Failure Patterns**:
   ```sql
   -- Check if specific BANs or source files fail consistently
   SELECT
     ban,
     source_tar_uri,
     source_member_path,
     failure_code,
     failure_message,
     COUNT(*) AS failure_count
   FROM `project.afp_pipeline.conversion_results`
   WHERE result_status = 'FAILED'
     AND failure_code IN ('BAD_AFP', 'CONVERTER_ERROR')
     AND processing_month = '2026-03'
   GROUP BY 1, 2, 3, 4, 5
   ORDER BY failure_count DESC
   LIMIT 50;
   ```

### Recovery Procedure

#### If AFP Version Is Unsupported

1. **Upgrade Converter**: Install newer converter version that supports the AFP version
2. **Requeue Affected Chunks**: After upgrade, requeue chunks
3. **Document Supported Versions**: Update documentation with supported AFP versions

#### If AFP Member Is Corrupt

1. **Request Re-Generation**: Contact source system to regenerate AFP
2. **Mark As Permanently Failed**: If re-generation is not possible
   ```sql
   -- Mark specific conversion results as permanently failed
   -- (This is informational; results table is append-only)
   ```

3. **Skip On Retry**: Worker should skip already-failed items on chunk retry

#### If Converter Has A Bug

1. **Report To Vendor**: Provide sample AFP file and error details
2. **Apply Patch**: Install converter patch when available
3. **Requeue Affected Chunks**: After patch, requeue chunks

### Prevention

1. **Validate AFP Files**: Implement AFP validation before conversion
2. **Test Converter**: Test converter with representative AFP samples
3. **Monitor Converter Errors**: Alert on high converter error rates
4. **Keep Converter Updated**: Apply converter updates regularly

## Failure Scenario 4: GCS Upload Failure

### Symptoms

- Worker logs show "Failed to upload PDF" or "GCS upload error"
- Failure code: `UPLOAD_FAILED`
- PDF was generated successfully but not uploaded
- Transient or persistent upload failures

### Root Causes

1. **Network Timeout**: Upload timed out due to network issues
2. **Permissions Error**: Worker SA lacks write permissions
3. **Bucket Does Not Exist**: Destination bucket was deleted
4. **Rate Limiting**: GCS rate limits exceeded
5. **Disk Full**: Worker ran out of disk space before upload

### Investigation Steps

1. **Check Worker Logs**:
   ```bash
   ssh afp-worker-01
   sudo journalctl -u afp-worker | grep -i "upload"
   ```

2. **Test GCS Upload Manually**:
   ```bash
   ssh afp-worker-01
   echo "test" > /tmp/test.txt
   gsutil cp /tmp/test.txt gs://afp-output-residential/test/test.txt
   ```

3. **Check Bucket Permissions**:
   ```bash
   gsutil iam get gs://afp-output-residential
   ```

4. **Check Bucket Existence**:
   ```bash
   gsutil ls gs://afp-output-residential
   ```

5. **Check Worker Disk Space**:
   ```bash
   ssh afp-worker-01
   df -h
   ```

6. **Review Upload Failure Patterns**:
   ```sql
   SELECT
     destination_uri,
     failure_message,
     COUNT(*) AS failure_count
   FROM `project.afp_pipeline.conversion_results`
   WHERE result_status = 'FAILED'
     AND failure_code = 'UPLOAD_FAILED'
     AND processing_month = '2026-03'
   GROUP BY 1, 2
   ORDER BY failure_count DESC;
   ```

### Recovery Procedure

#### If Permissions Error

1. **Grant Permissions**:
   ```bash
   # Grant objectCreator role to worker SA
   gsutil iam ch \
     serviceAccount:afp-worker@project.iam.gserviceaccount.com:roles/storage.objectCreator \
     gs://afp-output-residential
   ```

2. **Requeue Affected Chunks**:
   ```sql
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
       AND failure_code = 'UPLOAD_FAILED'
       AND failure_message LIKE '%permission%'
   )
   AND status = 'FAILED';
   ```

#### If Bucket Does Not Exist

1. **Create Bucket**:
   ```bash
   gsutil mb -l us-central1 gs://afp-output-residential
   ```

2. **Set Bucket Permissions**: Grant worker SA write access

3. **Requeue Affected Chunks**: See above

#### If Transient Network Error

1. **Verify Network Connectivity**: Check Cloud NAT and VPC configuration
2. **Increase Retry Logic**: Configure worker to retry uploads with backoff
3. **Monitor Network Metrics**: Set up alerts for network issues

#### If Rate Limiting

1. **Reduce Concurrency**: Reduce number of concurrent uploads per worker
2. **Request Quota Increase**: Contact GCP support for higher quotas
3. **Implement Backoff**: Add exponential backoff to upload retries

### Prevention

1. **Pre-Flight Checks**: Verify bucket existence and permissions at worker startup
2. **Retry Logic**: Implement robust retry logic with exponential backoff
3. **Monitor Upload Success Rate**: Alert on high upload failure rates
4. **Disk Space Monitoring**: Alert on low disk space before it becomes critical

## Failure Scenario 5: Repeated Chunk Failure

### Symptoms

- Chunk has `attempt_count >= 2`
- Chunk fails with same error on each retry
- Chunk reaches `max_attempts` and becomes terminally failed
- Multiple workers fail on the same chunk

### Root Causes

1. **Persistent Data Issue**: Source data is consistently bad
2. **Configuration Error**: Routing rule missing or incorrect
3. **Converter Bug**: Converter fails on specific input
4. **Resource Constraint**: Chunk is too large for available resources

### Investigation Steps

1. **Identify Repeatedly Failed Chunks**:
   ```sql
   SELECT
     shard_key,
     attempt_count,
     max_attempts,
     status,
     worker_id,
     updated_at
   FROM `project.afp_pipeline.work_locks`
   WHERE attempt_count >= 2
   ORDER BY attempt_count DESC, updated_at DESC;
   ```

2. **Analyze Failure Patterns**:
   ```sql
   SELECT
     r.shard_key,
     r.failure_code,
     r.failure_message,
     COUNT(*) AS failure_count,
     COUNT(DISTINCT r.worker_id) AS worker_count
   FROM `project.afp_pipeline.conversion_results` r
   JOIN `project.afp_pipeline.work_locks` w
     ON r.shard_key = w.shard_key
   WHERE w.attempt_count >= 2
     AND r.result_status = 'FAILED'
   GROUP BY 1, 2, 3
   ORDER BY failure_count DESC;
   ```

3. **Check Chunk Size**:
   ```sql
   SELECT
     shard_key,
     selected_ban_count,
     CAST(JSON_VALUE(metadata_json, '$.expected_conversion_count') AS INT64) AS expected_count
   FROM `project.afp_pipeline.work_locks`
   WHERE attempt_count >= 2
   ORDER BY selected_ban_count DESC;
   ```

4. **Review Worker Logs**: Check logs from workers that attempted the chunk

### Recovery Procedure

#### If Data Issue

1. **Identify Bad Data**:
   ```sql
   -- Find specific items that fail
   SELECT
     ban,
     source_tar_uri,
     source_member_path,
     failure_code,
     failure_message
   FROM `project.afp_pipeline.conversion_results`
   WHERE shard_key = '<problematic-shard-key>'
     AND result_status = 'FAILED'
   ORDER BY completed_at DESC;
   ```

2. **Request Data Fix**: Contact source system to fix bad data

3. **Mark As Permanently Failed**: If data cannot be fixed
   ```sql
   UPDATE `project.afp_pipeline.work_locks`
   SET
     status = 'FAILED',
     attempt_count = max_attempts,
     updated_at = CURRENT_TIMESTAMP(),
     completed_at = CURRENT_TIMESTAMP()
   WHERE shard_key = '<problematic-shard-key>';
   ```

#### If Configuration Error

1. **Fix Configuration**: Update routing rules or other config

2. **Redeploy Workers**: Deploy updated configuration

3. **Requeue Chunk**:
   ```sql
   UPDATE `project.afp_pipeline.work_locks`
   SET
     status = 'PENDING',
     attempt_count = 0,
     worker_id = NULL,
     lease_token = NULL,
     lease_expires_at = NULL,
     updated_at = CURRENT_TIMESTAMP()
   WHERE shard_key = '<problematic-shard-key>';
   ```

#### If Chunk Is Too Large

1. **Split Chunk**: Replan with smaller `target_ban_count`

2. **Increase VM Resources**: Use larger VM machine type

3. **Optimize Worker**: Reduce memory usage or process items in smaller batches

### Prevention

1. **Monitor Retry Rate**: Alert on high retry rates
2. **Validate Data Early**: Implement data validation before chunking
3. **Test Configuration**: Test routing rules before deployment
4. **Right-Size Chunks**: Tune `target_ban_count` based on observed performance

## Failure Scenario 6: BigQuery Transient Errors

### Symptoms

- Worker logs show "BigQuery API error" or "Deadline exceeded"
- Intermittent failures claiming chunks or writing results
- Errors resolve on retry

### Root Causes

1. **API Rate Limiting**: Too many concurrent requests
2. **Quota Exceeded**: BigQuery quota limits reached
3. **Network Issues**: Transient network problems
4. **BigQuery Service Issues**: Temporary BigQuery outage

### Investigation Steps

1. **Check BigQuery Quotas**:
   - Go to GCP Console > IAM & Admin > Quotas
   - Search for "BigQuery API"
   - Check current usage vs limits

2. **Check BigQuery Service Status**:
   - Visit https://status.cloud.google.com/
   - Check for BigQuery incidents

3. **Review Error Patterns**:
   ```bash
   # Check worker logs for BigQuery errors
   ssh afp-worker-01
   sudo journalctl -u afp-worker | grep -i "bigquery"
   ```

### Recovery Procedure

1. **Implement Retry Logic**: Workers should already retry BigQuery operations

2. **Add Backoff**: Increase backoff duration between retries

3. **Reduce Concurrency**: Reduce number of concurrent BigQuery operations

4. **Request Quota Increase**: If hitting quota limits consistently

### Prevention

1. **Implement Robust Retry Logic**: Exponential backoff with jitter
2. **Monitor Quotas**: Alert when approaching quota limits
3. **Batch Operations**: Batch BigQuery writes where possible
4. **Use Streaming Inserts Carefully**: Streaming inserts have different quotas

## Summary of Failure Codes

| Failure Code | Meaning | Recovery Strategy |
|--------------|---------|-------------------|
| `BAD_TAR` | Source tar file is corrupt or unreadable | Request re-upload, requeue after fix |
| `BAD_AFP` | AFP member is corrupt or unsupported | Request re-generation or upgrade converter |
| `CONVERTER_ERROR` | Converter binary failed | Check converter logs, report bug, apply patch |
| `OUTPUT_VALIDATION_FAILED` | PDF output failed validation | Investigate converter output, fix validation logic |
| `UPLOAD_FAILED` | GCS upload failed | Check permissions, network, disk space |
| `MANIFEST_ERROR` | Chunk manifest is malformed | Replan chunk, fix planner logic |
| `LEASE_LOST` | Worker lost lease during processing | Automatic reclaim by another worker |
| `NO_ROUTING_RULE` | No routing rule matched | Add routing rule, redeploy, requeue |
| `ROUTING_TEMPLATE_ERROR` | Routing template variable missing | Fix routing config, redeploy, requeue |
| `UNKNOWN` | Unexpected error | Investigate logs, report to development team |

## Escalation Criteria

Escalate to development team when:

- New or unknown failure codes appear
- Failure rate exceeds 10% for more than 1 hour
- Repeated failures with no clear root cause
- System-wide issues affecting multiple workers
- Data corruption or schema mismatches
- Performance degradation with no clear cause

## Related Documents

- [`runbook.md`](runbook.md): Operational procedures
- [`architecture.md`](architecture.md): System architecture and design decisions
- [`worker-processing.md`](worker-processing.md): Worker processing flow
- [`diagrams/failure_retry_diagram.md`](diagrams/failure_retry_diagram.md): Failure and retry flow diagram