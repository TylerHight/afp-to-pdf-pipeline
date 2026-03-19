# Testing Strategy

## Purpose

This document defines the testing approach for the AFP-to-PDF pipeline, including unit tests, integration tests, local smoke tests, one-month rehearsal tests, failure injection tests, and acceptance criteria for production readiness.

## Scope

This document covers:

- testing philosophy and principles
- unit testing strategy
- integration testing strategy
- end-to-end testing strategy
- performance testing
- failure injection testing
- one-month rehearsal test
- acceptance criteria for production readiness
- test data requirements
- test environment setup

This document does not cover:

- production monitoring (see runbook.md)
- operational procedures (see runbook.md)
- deployment procedures (see deployment-guide.md)

## Testing Philosophy

### Principles

1. **Test Early, Test Often**: Catch issues before they reach production
2. **Test Realistically**: Use representative data and realistic scenarios
3. **Test Failures**: Verify system handles failures gracefully
4. **Test at Multiple Levels**: Unit, integration, and end-to-end tests
5. **Automate Where Possible**: Reduce manual testing burden
6. **Document Test Results**: Track what was tested and what passed/failed

### Testing Pyramid

```
        /\
       /  \      E2E Tests (Few)
      /____\     - One-month rehearsal
     /      \    - Full pipeline tests
    /________\   Integration Tests (Some)
   /          \  - Planner + BigQuery
  /____________\ - Worker + GCS + Converter
 /              \ Unit Tests (Many)
/______________\ - Individual functions
                 - Data validation
                 - Business logic
```

## Unit Testing

### Scope

Unit tests verify individual functions and classes in isolation.

### Components to Unit Test

#### Planner

- **Inventory Building**: Test source tar enumeration and metadata extraction
- **Deterministic Sorting**: Verify sort order is consistent
- **Chunk Splitting**: Test chunk boundary logic and size limits
- **Manifest Generation**: Verify manifest structure and content
- **Lock Row Creation**: Test work_locks row generation

#### Worker

- **Manifest Loading**: Test manifest parsing and validation
- **Tar Extraction**: Test AFP member extraction and filtering
- **Converter Invocation**: Test converter command construction
- **PDF Validation**: Test PDF signature and size checks
- **Routing Resolution**: Test routing rule matching and precedence
- **Result Recording**: Test conversion_results row generation

#### Shared Utilities

- **GCS Operations**: Test upload, download, list operations
- **BigQuery Operations**: Test query, insert, update operations
- **Configuration Loading**: Test config file parsing
- **Retry Logic**: Test exponential backoff and retry limits

### Unit Test Framework

**Language**: Python

**Framework**: `pytest`

**Mocking**: `unittest.mock` or `pytest-mock`

### Example Unit Tests

```python
# test_planner.py
import pytest
from planner.chunking import split_into_chunks

def test_split_into_chunks_respects_target_count():
    """Test that chunks don't exceed target_ban_count"""
    entries = [{"ban": f"{i:08d}"} for i in range(100000)]
    target_ban_count = 25000
    
    chunks = split_into_chunks(entries, target_ban_count)
    
    for chunk in chunks:
        assert len(chunk["entries"]) <= target_ban_count

def test_split_into_chunks_deterministic():
    """Test that chunking is deterministic"""
    entries = [{"ban": f"{i:08d}"} for i in range(50000)]
    target_ban_count = 25000
    
    chunks1 = split_into_chunks(entries, target_ban_count)
    chunks2 = split_into_chunks(entries, target_ban_count)
    
    assert chunks1 == chunks2

# test_worker.py
import pytest
from worker.routing import resolve_destination

def test_routing_matches_first_rule():
    """Test that routing uses first matching rule"""
    rules = [
        {"priority": 100, "conditions": {"month": "2026-03"}, "bucket": "bucket-a"},
        {"priority": 90, "conditions": {"month": "2026-03"}, "bucket": "bucket-b"}
    ]
    metadata = {"month": "2026-03"}
    
    destination = resolve_destination(rules, metadata)
    
    assert destination["bucket"] == "bucket-a"

def test_routing_no_match_raises_error():
    """Test that routing raises error when no rule matches"""
    rules = [
        {"priority": 100, "conditions": {"month": "2026-03"}, "bucket": "bucket-a"}
    ]
    metadata = {"month": "2026-02"}
    
    with pytest.raises(ValueError, match="No routing rule matched"):
        resolve_destination(rules, metadata)
```

### Running Unit Tests

```bash
# Install test dependencies
pip install pytest pytest-cov pytest-mock

# Run all unit tests
pytest tests/unit/

# Run with coverage
pytest --cov=src tests/unit/

# Run specific test file
pytest tests/unit/test_planner.py

# Run specific test
pytest tests/unit/test_planner.py::test_split_into_chunks_respects_target_count
```

### Unit Test Coverage Goals

- **Planner**: 80% code coverage
- **Worker**: 80% code coverage
- **Shared Utilities**: 90% code coverage

## Integration Testing

### Scope

Integration tests verify that components work together correctly.

### Integration Test Scenarios

#### Planner + BigQuery

**Test**: Planner can seed work_locks table

**Steps**:
1. Set up test BigQuery dataset
2. Run planner with test data
3. Verify work_locks rows created
4. Verify manifest files written to GCS
5. Verify row counts and checksums match

**Expected Result**: work_locks table populated with correct chunk metadata

#### Worker + GCS + Converter

**Test**: Worker can process a chunk end-to-end

**Steps**:
1. Create test manifest and tar file
2. Seed test work_locks row
3. Run worker to claim and process chunk
4. Verify PDFs written to output bucket
5. Verify conversion_results rows written
6. Verify work_locks row marked DONE

**Expected Result**: Chunk processed successfully, results recorded

#### Worker + Routing Rules

**Test**: Worker routes PDFs to correct destinations

**Steps**:
1. Create test routing rules config
2. Create test data with different routing dimensions
3. Run worker to process test chunk
4. Verify PDFs written to correct buckets/prefixes

**Expected Result**: PDFs routed according to rules

#### Planner + Worker + Reporting

**Test**: End-to-end progress reporting

**Steps**:
1. Run planner to create chunks
2. Run workers to process chunks
3. Query reporting views
4. Verify progress calculations are correct

**Expected Result**: Reporting views show accurate progress

### Integration Test Environment

**Infrastructure**:
- Test GCP project or isolated test dataset
- Test GCS buckets
- Test BigQuery dataset
- Test VMs or local Docker containers

**Test Data**:
- Small representative tar files (100-1000 invoices)
- Sample AFP files covering different formats
- Test routing rules config

### Running Integration Tests

```bash
# Set up test environment
export TEST_PROJECT_ID="afp-pipeline-test"
export TEST_BUCKET="afp-test-bucket"
export TEST_DATASET="afp_pipeline_test"

# Run integration tests
pytest tests/integration/

# Run specific integration test
pytest tests/integration/test_planner_bigquery.py
```

## End-to-End Testing

### Scope

End-to-end tests verify the entire pipeline from source upload to PDF output.

### E2E Test Scenarios

#### Happy Path

**Test**: Process one day of data successfully

**Steps**:
1. Upload test tar file to input bucket
2. Run planner to create chunks
3. Start workers
4. Wait for all chunks to complete
5. Verify all expected PDFs exist
6. Verify conversion_results show 100% success
7. Verify reporting views show correct progress

**Expected Result**: All invoices converted successfully

#### Partial Failure Path

**Test**: Handle some failed conversions gracefully

**Steps**:
1. Upload tar file with some corrupt AFP members
2. Run planner and workers
3. Verify successful conversions complete
4. Verify failed conversions recorded with failure codes
5. Verify chunk completes with partial success

**Expected Result**: Successful items processed, failures recorded

#### Retry Path

**Test**: Retry failed chunks successfully

**Steps**:
1. Process chunk that fails on first attempt
2. Fix underlying issue (e.g., permissions)
3. Requeue chunk
4. Verify chunk succeeds on retry
5. Verify attempt_count incremented

**Expected Result**: Chunk succeeds after retry

### Running E2E Tests

```bash
# Run E2E tests (requires full test environment)
pytest tests/e2e/

# Run with verbose output
pytest -v tests/e2e/
```

## Performance Testing

### Scope

Performance tests verify the system meets throughput and latency requirements.

### Performance Test Scenarios

#### Throughput Test

**Test**: Verify system can process target volume

**Metrics**:
- Conversions per hour per worker
- Chunks per hour
- Time to complete one month

**Target**: 1 month per day (approximately 30 days of data in 24 hours)

**Steps**:
1. Load one month of representative data
2. Run planner and workers
3. Measure throughput over time
4. Verify target throughput achieved

#### Scalability Test

**Test**: Verify system scales with worker count

**Steps**:
1. Process same workload with 6, 12, and 24 workers
2. Measure throughput for each configuration
3. Verify near-linear scaling

**Expected Result**: Throughput increases proportionally with worker count

#### Stress Test

**Test**: Verify system handles peak load

**Steps**:
1. Load 2-3 months of data simultaneously
2. Run planner and workers
3. Monitor resource utilization
4. Verify system remains stable

**Expected Result**: System processes all data without crashes or data loss

### Performance Monitoring

**Metrics to Track**:
- Worker CPU and memory utilization
- Disk I/O rates
- Network throughput
- BigQuery query latency
- GCS upload/download latency
- Converter execution time
- End-to-end chunk duration

## Failure Injection Testing

### Scope

Failure injection tests verify the system handles failures gracefully.

### Failure Injection Scenarios

#### VM Crash

**Test**: Worker VM crashes mid-chunk

**Steps**:
1. Start worker processing a chunk
2. Kill worker process or stop VM
3. Wait for lease to expire
4. Verify another worker reclaims chunk
5. Verify chunk completes successfully

**Expected Result**: Chunk recovered and completed by another worker

#### Network Partition

**Test**: Worker loses network connectivity

**Steps**:
1. Start worker processing a chunk
2. Block network traffic to/from worker
3. Wait for lease to expire
4. Restore network
5. Verify chunk reclaimed by another worker

**Expected Result**: Chunk recovered after network restored

#### BigQuery Transient Error

**Test**: BigQuery API returns transient error

**Steps**:
1. Mock BigQuery client to return transient error
2. Run worker to claim chunk
3. Verify worker retries with backoff
4. Verify worker eventually succeeds

**Expected Result**: Worker retries and succeeds

#### GCS Upload Failure

**Test**: GCS upload fails transiently

**Steps**:
1. Mock GCS client to fail upload
2. Run worker to process chunk
3. Verify worker retries upload
4. Verify worker eventually succeeds or records failure

**Expected Result**: Worker retries and succeeds or fails gracefully

#### Corrupt Source Data

**Test**: Tar file is corrupt

**Steps**:
1. Upload corrupt tar file
2. Run planner and workers
3. Verify workers detect corruption
4. Verify failures recorded with BAD_TAR code
5. Verify chunk marked as failed

**Expected Result**: Corruption detected and recorded

### Running Failure Injection Tests

```bash
# Run failure injection tests
pytest tests/failure_injection/

# Run specific failure test
pytest tests/failure_injection/test_vm_crash.py
```

## One-Month Rehearsal Test

### Purpose

The one-month rehearsal test is a full-scale test using representative production data to validate the system is ready for production.

### Rehearsal Test Plan

#### Preparation

1. **Select Test Month**: Choose a representative month (e.g., March 2025)
2. **Prepare Test Data**: Copy production tar files to test environment
3. **Set Up Test Environment**: Deploy full infrastructure in test project
4. **Configure Monitoring**: Set up dashboards and alerts
5. **Prepare Team**: Brief operations team on test procedures

#### Execution

**Day 1: Planning and Initial Processing**

1. Upload tar files to test input bucket
2. Run planner to create chunks
3. Start all 12 workers
4. Monitor initial processing for 4-6 hours
5. Verify chunks are being claimed and processed
6. Check for any immediate issues

**Day 2-3: Steady State Processing**

1. Monitor progress continuously
2. Track throughput and remaining work
3. Investigate any failures
4. Verify retry logic working
5. Check resource utilization

**Day 4: Completion and Validation**

1. Verify all chunks completed or failed
2. Validate conversion results
3. Check reporting views
4. Verify PDF outputs
5. Calculate actual throughput

#### Success Criteria

- **Completion**: 95%+ of expected conversions succeed
- **Throughput**: Achieve "1 month per day" target (or document actual rate)
- **Failures**: All failures have clear failure codes and messages
- **Recovery**: All transient failures recovered automatically
- **Reporting**: Progress views show accurate data
- **Stability**: No worker crashes or data corruption

#### Validation Steps

1. **Count Validation**:
   ```sql
   SELECT
     expected_conversions,
     successful_conversions,
     failed_attempts,
     completion_pct
   FROM `project.afp_pipeline.vw_month_progress`
   WHERE processing_month = '2025-03';
   ```

2. **Output Validation**:
   ```bash
   # Count PDFs in output buckets
   gsutil du -s gs://afp-output-*/
   
   # Sample PDFs for manual inspection
   gsutil cp gs://afp-output-residential/invoices/2025-03/sample.pdf /tmp/
   ```

3. **Failure Analysis**:
   ```sql
   SELECT
     failure_code,
     COUNT(*) as failure_count,
     COUNT(DISTINCT ban) as affected_bans
   FROM `project.afp_pipeline.conversion_results`
   WHERE result_status = 'FAILED'
     AND processing_month = '2025-03'
   GROUP BY failure_code
   ORDER BY failure_count DESC;
   ```

4. **Performance Analysis**:
   ```sql
   SELECT
     worker_id,
     success_count,
     avg_duration_seconds
   FROM `project.afp_pipeline.vw_worker_throughput`
   WHERE processing_month = '2025-03'
   ORDER BY success_count DESC;
   ```

### Rehearsal Test Report

Document the following:

- **Test Date**: When the test was run
- **Test Duration**: How long it took to complete
- **Throughput Achieved**: Actual conversions per hour
- **Success Rate**: Percentage of successful conversions
- **Failure Analysis**: Breakdown of failure codes
- **Issues Encountered**: Any problems and how they were resolved
- **Lessons Learned**: What was learned from the test
- **Recommendations**: Changes needed before production

## Acceptance Criteria for Production Readiness

### Functional Criteria

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] All E2E tests pass
- [ ] One-month rehearsal test completed successfully
- [ ] Planner creates deterministic chunks
- [ ] Workers process chunks correctly
- [ ] Routing rules work as expected
- [ ] Reporting views show accurate data
- [ ] Failure recovery works automatically

### Performance Criteria

- [ ] Throughput meets or exceeds target (1 month per day)
- [ ] Worker resource utilization is acceptable (<80% CPU, <80% memory)
- [ ] No memory leaks detected
- [ ] Chunk duration is predictable and consistent
- [ ] BigQuery queries complete in <5 seconds
- [ ] GCS operations complete in <30 seconds

### Reliability Criteria

- [ ] System recovers from VM crashes automatically
- [ ] System recovers from network failures automatically
- [ ] System handles corrupt data gracefully
- [ ] Retry logic works correctly
- [ ] No data loss or corruption
- [ ] Idempotency guarantees hold

### Operational Criteria

- [ ] Monitoring dashboards configured
- [ ] Alerts configured and tested
- [ ] Runbook documented and reviewed
- [ ] Failure handling procedures documented
- [ ] Deployment procedures documented
- [ ] Operations team trained
- [ ] On-call rotation established

### Documentation Criteria

- [ ] Architecture documentation complete
- [ ] API/interface documentation complete
- [ ] Configuration documentation complete
- [ ] Troubleshooting guide complete
- [ ] Runbook complete
- [ ] Deployment guide complete

### Security Criteria

- [ ] Service accounts follow least privilege
- [ ] IAM permissions reviewed and approved
- [ ] No hardcoded credentials
- [ ] Secrets managed securely
- [ ] Network security configured (VPC, firewall rules)
- [ ] Audit logging enabled

## Test Data Requirements

### Test Data Characteristics

**Volume**:
- Small: 100-1,000 invoices (for unit/integration tests)
- Medium: 10,000-50,000 invoices (for E2E tests)
- Large: 500,000-1,000,000 invoices (for rehearsal test)

**Variety**:
- Different AFP versions
- Different invoice types
- Different line of business
- Different statement dates
- Edge cases (empty, very large, corrupt)

**Realism**:
- Representative of production data
- Includes typical failure scenarios
- Covers all routing rules

### Test Data Generation

```bash
# Generate test invoices
./scripts/mock_data/generate_test_invoices.sh \
  --count 1000 \
  --output /tmp/test-invoices \
  --format afp

# Create test tar file
tar -czf /tmp/test-2026-03-01.tar /tmp/test-invoices/

# Upload to test bucket
gsutil cp /tmp/test-2026-03-01.tar gs://afp-input-test/monthly/2026-03/
```

## Test Environment Setup

### Local Development Environment

```bash
# Install dependencies
pip install -r requirements.txt
pip install -r requirements-test.txt

# Set up local test database (if needed)
docker run -d -p 5432:5432 postgres:13

# Run tests
pytest tests/
```

### Test GCP Project

```bash
# Create test project
gcloud projects create afp-pipeline-test

# Deploy test infrastructure
cd infrastructure/terraform
terraform workspace new test
terraform apply -var-file=test.tfvars
```

## Continuous Integration

### CI Pipeline

```yaml
# .github/workflows/test.yml
name: Test Pipeline

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
        with:
          python-version: '3.9'
      - run: pip install -r requirements.txt -r requirements-test.txt
      - run: pytest tests/unit/ --cov=src

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
      - run: pip install -r requirements.txt -r requirements-test.txt
      - run: pytest tests/integration/
```

## Related Documents

- [`architecture.md`](architecture.md): System architecture
- [`runbook.md`](runbook.md): Operational procedures
- [`failure-handling.md`](failure-handling.md): Failure scenarios and recovery
- [`deployment-guide.md`](deployment-guide.md): Deployment procedures