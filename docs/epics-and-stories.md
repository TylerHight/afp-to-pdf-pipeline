# Epics and User Stories - Kanban Board

## Kanban Board

### 📋 Backlog
Stories ready to be worked on, prioritized top to bottom

### 🔨 In Progress
- **Tyler**: (max 2 stories)
- **Riyanshi**: (max 2 stories)

### 👀 Review
Stories complete and awaiting review/testing

### ✅ Done
Stories completed and verified

---

## Team Structure

- **Tyler**: Focus on Planner, BigQuery, Reporting
- **Riyanshi**: Focus on Worker, Converter Integration, Output Routing
- **Shared**: Schema design, validation, integration, deployment

## Epic Overview

| Epic | Owner | Status |
|------|-------|--------|
| Epic 1: Foundation & Infrastructure | Tyler & Riyanshi | Not Started |
| Epic 2: Planner Implementation | Tyler | Not Started |
| Epic 3: Worker Implementation | Riyanshi | Not Started |
| Epic 4: Integration & Validation | Tyler & Riyanshi | Not Started |
| Epic 5: Hardening & Production Prep | Tyler & Riyanshi | Not Started |

---

## Epic 1: Foundation & Infrastructure (Month 1)

**Goal**: Set up GCP infrastructure, schemas, and development environment

**Acceptance Criteria**:
- [ ] GCP project configured with all required APIs
- [ ] Service accounts created with correct permissions
- [ ] GCS buckets created and accessible
- [ ] BigQuery dataset and tables created
- [ ] VMs provisioned and accessible
- [ ] Development environment set up locally

### Stories

#### Story 1.1: GCP Project Setup
**Owner**: Tyler | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-1-gcp-project-setup), [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md)
**Tasks**:
- Create GCP project
- Enable required APIs (Compute, Storage, BigQuery, Logging)
- Set up billing
- Configure IAM roles

#### Story 1.2: Service Account Creation
**Owner**: Tyler | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-2-service-account-creation), [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md#service-accounts)
**Tasks**:
- Create planner service account
- Create worker service account
- Create admin service account
- Grant appropriate IAM permissions

#### Story 1.3: Network Setup
**Owner**: Tyler | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-3-network-setup), [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md#network-topology)
**Tasks**:
- Create VPC network and subnet
- Create Cloud NAT
- Configure firewall rules
- Test connectivity

#### Story 1.4: GCS Bucket Setup
**Owner**: Tyler | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-4-gcs-bucket-creation), [`architecture.md`](architecture.md#input-bucket), [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md#storage-layer)
**Tasks**:
- Create input bucket
- Create manifest bucket
- Create output buckets (residential, business, archive)
- Set bucket permissions
- Configure lifecycle policies

#### Story 1.5: BigQuery Schema Implementation
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 1.1
**References**: [`bigquery-schema.md`](bigquery-schema.md) ⭐ CRITICAL, [`deployment-guide.md`](deployment-guide.md#step-5-bigquery-setup), [`conversion-results.md`](conversion-results.md)
**Tasks**:
- Create `afp_pipeline` dataset
- Create `work_locks` table with partitioning/clustering
- Create `conversion_results` table with partitioning/clustering
- Create reporting views (vw_month_progress, vw_chunk_progress, vw_worker_throughput, vw_stale_and_retried_chunks)
- Test queries against empty tables

#### Story 1.6: VM Provisioning
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 1.2, Story 1.3
**References**: [`deployment-guide.md`](deployment-guide.md#step-6-vm-creation), [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md#compute-layer)
**Tasks**:
- Create controller VM
- Create 12 worker VMs
- Configure startup scripts
- Test SSH access via IAP
- Install base dependencies (Python, pip, git)

#### Story 1.7: Local Development Environment
**Owner**: Tyler & Riyanshi | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-7-application-deployment), [`testing-strategy.md`](testing-strategy.md#local-development-environment)
**Tasks**:
- Set up Python virtual environment
- Install dependencies (google-cloud-storage, google-cloud-bigquery)
- Configure local credentials
- Create project README with setup instructions

#### Story 1.8: Terraform Infrastructure as Code
**Owner**: Tyler | **Effort**: 3 days | **Status**: Backlog
**Optional**: Can be done in parallel or deferred
**References**: [`deployment-guide.md`](deployment-guide.md#step-10-terraform-deployment-alternative)
**Tasks**:
- Create Terraform modules for service accounts, buckets, BigQuery, VMs
- Test Terraform apply/destroy
- Document Terraform usage

---

## Epic 2: Planner Implementation (Month 2)

**Goal**: Build the planner that creates deterministic chunks and seeds work_locks

**Acceptance Criteria**:
- [ ] Planner can scan source tar inventory
- [ ] Planner creates deterministic chunks
- [ ] Planner writes manifest files to GCS
- [ ] Planner seeds work_locks table
- [ ] Planner is idempotent (safe to rerun)

### Stories

#### Story 2.1: Source Inventory Scanner
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**References**: [`planner-and-chunking.md`](planner-and-chunking.md#source-inventory-model) ⭐ CRITICAL, [`architecture.md`](architecture.md#planner--chunk-seeding-job), [`diagrams/planner_chunking_diagram.md`](diagrams/planner_chunking_diagram.md)
**Tasks**:
- Implement GCS tar file listing
- Extract metadata from tar files (BAN, statement_date, AFP member paths)
- Build in-memory inventory structure
- Add logging

#### Story 2.2: Deterministic Sorting and Chunking
**Owner**: Tyler | **Effort**: 3 days | **Status**: Backlog
**Dependencies**: Story 2.1
**References**: [`planner-and-chunking.md`](planner-and-chunking.md#deterministic-chunking-rules) ⭐ CRITICAL, [`architecture.md`](architecture.md#chunking-model), [`testing-strategy.md`](testing-strategy.md#unit-testing)
**Tasks**:
- Implement deterministic sort (statement_date, BAN, tar URI, member path)
- Implement chunk splitting logic with target_ban_count
- Assign chunk_index and priority
- Calculate expected_conversion_count
- Add unit tests

#### Story 2.3: Manifest File Generation
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 2.2
**References**: [`planner-and-chunking.md`](planner-and-chunking.md#manifest-contract) ⭐ CRITICAL, [`architecture.md`](architecture.md#ban-list-file-contract)
**Tasks**:
- Implement manifest JSON structure per spec
- Write manifests to GCS
- Calculate and store manifest checksum
- Add validation logic

#### Story 2.4: Work Locks Seeding
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 2.3
**References**: [`planner-and-chunking.md`](planner-and-chunking.md#work_locks-seeding-contract) ⭐ CRITICAL, [`bigquery-schema.md`](bigquery-schema.md#table-1-work_locks), [`architecture.md`](architecture.md#work_locks-row-contract)
**Tasks**:
- Implement work_locks row generation
- Insert rows into BigQuery
- Handle idempotency (check for existing shard_key)
- Add error handling and retries

#### Story 2.5: Planner CLI and Configuration
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**References**: [`planner-and-chunking.md`](planner-and-chunking.md#planner-responsibilities), [`architecture.md`](architecture.md#planner--chunk-seeding-job)
**Tasks**:
- Create command-line interface
- Add configuration file support (YAML)
- Add --month parameter for manual runs
- Add dry-run mode
- Add logging and progress output

#### Story 2.6: Planner Testing
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**References**: [`testing-strategy.md`](testing-strategy.md#unit-testing) ⭐ CRITICAL, [`planner-and-chunking.md`](planner-and-chunking.md#planning-validations)
**Tasks**:
- Create test data (small tar files)
- Write unit tests for chunking logic
- Write integration test for end-to-end planner run
- Test idempotency

---

## Epic 3: Worker Implementation (Month 2-3)

**Goal**: Build the worker daemon that processes chunks

**Acceptance Criteria**:
- [ ] Worker can claim chunks from work_locks
- [ ] Worker can download and process tar files
- [ ] Worker can invoke converter
- [ ] Worker can route PDFs to correct destinations
- [ ] Worker writes conversion_results
- [ ] Worker completes or fails chunks correctly

### Stories

#### Story 3.1: Worker Lease Management
**Owner**: Riyanshi | **Effort**: 3 days | **Status**: Backlog
**References**: [`worker-processing.md`](worker-processing.md#runtime-flow) ⭐ CRITICAL, [`architecture.md`](architecture.md#lease-validations), [`diagrams/work_lock_lifecycle_diagram.md`](diagrams/work_lock_lifecycle_diagram.md)
**Tasks**:
- Implement chunk claim logic (query + update work_locks)
- Implement heartbeat loop
- Implement lease expiry detection
- Implement chunk completion/failure
- Add retry logic with backoff

#### Story 3.2: Manifest Loading and Validation
**Owner**: Riyanshi | **Effort**: 1 day | **Status**: Backlog
**Dependencies**: Story 3.1
**References**: [`worker-processing.md`](worker-processing.md#3-load-chunk-definition) ⭐ CRITICAL, [`planner-and-chunking.md`](planner-and-chunking.md#manifest-contract)
**Tasks**:
- Download manifest from GCS
- Parse and validate manifest JSON
- Verify checksum
- Extract entries list

#### Story 3.3: Tar Download and AFP Extraction
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 3.2
**References**: [`worker-processing.md`](worker-processing.md#source-file-processing) ⭐ CRITICAL, [`architecture.md`](architecture.md#input-validations), [`failure-handling.md`](failure-handling.md#failure-scenario-2-bad-tar-file)
**Tasks**:
- Download tar file from GCS
- Extract specific AFP members per manifest
- Handle tar errors gracefully
- Clean up temporary files

#### Story 3.4: Converter Integration
**Owner**: Riyanshi | **Effort**: 3 days | **Status**: Backlog
**Dependencies**: Story 3.3
**References**: [`worker-processing.md`](worker-processing.md#6-invoke-converter) ⭐ CRITICAL, [`deployment-guide.md`](deployment-guide.md#step-8-afp-converter-installation), [`failure-handling.md`](failure-handling.md#failure-scenario-3-corrupt-afp-member)
**Tasks**:
- Install converter on worker VMs
- Implement converter invocation wrapper
- Capture converter exit code and output
- Handle converter errors
- Add timeout logic

#### Story 3.5: PDF Validation
**Owner**: Riyanshi | **Effort**: 1 day | **Status**: Backlog
**Dependencies**: Story 3.4
**References**: [`worker-processing.md`](worker-processing.md#7-validate-pdf-output) ⭐ CRITICAL, [`architecture.md`](architecture.md#conversion-validations)
**Tasks**:
- Check PDF file exists
- Verify PDF size > 0
- Verify PDF signature header
- Add validation error codes

#### Story 3.6: Routing Rules Implementation
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`routing-rules.md`](routing-rules.md) ⭐ CRITICAL, [`worker-processing.md`](worker-processing.md#8-route-output), [`architecture.md`](architecture.md#routing-rules-config)
**Tasks**:
- Implement routing rules config loader (YAML)
- Implement rule matching logic (priority, conditions)
- Implement template variable substitution
- Handle no-match case
- Add unit tests

#### Story 3.7: GCS Upload and Result Recording
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 3.5, Story 3.6
**References**: [`worker-processing.md`](worker-processing.md#9-write-conversion_results) ⭐ CRITICAL, [`conversion-results.md`](conversion-results.md), [`bigquery-schema.md`](bigquery-schema.md#table-2-conversion_results), [`failure-handling.md`](failure-handling.md#failure-scenario-4-gcs-upload-failure)
**Tasks**:
- Upload PDF to destination bucket
- Write conversion_results row to BigQuery
- Handle upload failures with retry
- Implement idempotency checks

#### Story 3.8: Worker Main Loop and Configuration
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`worker-processing.md`](worker-processing.md) ⭐ CRITICAL, [`diagrams/worker_processing_diagram.md`](diagrams/worker_processing_diagram.md), [`architecture.md`](architecture.md#worker-daemon-on-12-linux-vms)
**Tasks**:
- Implement main worker loop (claim → process → complete)
- Add configuration file support
- Add graceful shutdown handling
- Add logging throughout

#### Story 3.9: Worker systemd Service
**Owner**: Riyanshi | **Effort**: 1 day | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md#step-9-systemd-service-configuration), [`runbook.md`](runbook.md#starting-and-stopping-workers)
**Tasks**:
- Create systemd service file
- Deploy to all worker VMs
- Test start/stop/restart
- Configure auto-restart on failure

#### Story 3.10: Worker Testing
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`testing-strategy.md`](testing-strategy.md#unit-testing) ⭐ CRITICAL, [`worker-processing.md`](worker-processing.md), [`failure-handling.md`](failure-handling.md)
**Tasks**:
- Write unit tests for routing logic
- Write integration test for worker processing one chunk
- Test failure scenarios (bad tar, converter error, upload failure)

---

## Epic 4: Integration & Validation (Month 3-4)

**Goal**: Integrate planner and workers, validate end-to-end flow, add monitoring

**Acceptance Criteria**:
- [ ] Planner and workers work together end-to-end
- [ ] One-month test data processed successfully
- [ ] Reporting views show accurate data
- [ ] Monitoring and alerting configured
- [ ] Failure scenarios tested and handled

### Stories

#### Story 4.1: End-to-End Integration Test
**Owner**: Tyler & Riyanshi | **Effort**: 3 days | **Status**: Backlog
**Dependencies**: Epic 2, Epic 3
**References**: [`testing-strategy.md`](testing-strategy.md#end-to-end-testing) ⭐ CRITICAL, [`architecture.md`](architecture.md#end-to-end-flow), [`diagrams/architecture_diagram.md`](diagrams/architecture_diagram.md)
**Tasks**:
- Create test data (1 month, ~10K invoices)
- Run planner to create chunks
- Start workers to process chunks
- Verify all chunks complete
- Verify PDFs exist in output buckets
- Verify conversion_results accurate

#### Story 4.2: Reporting Views Validation
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 4.1
**References**: [`conversion-results.md`](conversion-results.md#progress-logic) ⭐ CRITICAL, [`bigquery-schema.md`](bigquery-schema.md#reporting-views), [`diagrams/reporting_progress_diagram.md`](diagrams/reporting_progress_diagram.md)
**Tasks**:
- Query all reporting views
- Verify progress calculations correct
- Verify remaining work calculation correct
- Test views with partial completion
- Document query examples

#### Story 4.3: Failure Scenario Testing
**Owner**: Tyler & Riyanshi | **Effort**: 3 days | **Status**: Backlog
**References**: [`failure-handling.md`](failure-handling.md) ⭐ CRITICAL, [`testing-strategy.md`](testing-strategy.md#failure-injection-testing), [`diagrams/failure_retry_diagram.md`](diagrams/failure_retry_diagram.md)
**Tasks**:
- Test VM crash and lease expiry
- Test bad tar file handling
- Test corrupt AFP handling
- Test upload failure and retry
- Test repeated chunk failure
- Verify all failures recorded correctly

#### Story 4.4: Monitoring Setup
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**References**: [`runbook.md`](runbook.md#monitoring-pipeline-health), [`architecture.md`](architecture.md#operational-observability), [`diagrams/reporting_progress_diagram.md`](diagrams/reporting_progress_diagram.md)
**Tasks**:
- Create Cloud Monitoring dashboard
- Add metrics for worker health, throughput, failures
- Configure log-based metrics
- Test dashboard with live data

#### Story 4.5: Alerting Configuration
**Owner**: Tyler | **Effort**: 2 days | **Status**: Backlog
**Dependencies**: Story 4.4
**References**: [`runbook.md`](runbook.md#monitoring-pipeline-health), [`diagrams/reporting_progress_diagram.md`](diagrams/reporting_progress_diagram.md#alerting-thresholds)
**Tasks**:
- Configure alerts for stale leases
- Configure alerts for high failure rate
- Configure alerts for worker downtime
- Test alert delivery

#### Story 4.6: Performance Testing
**Owner**: Tyler & Riyanshi | **Effort**: 3 days | **Status**: Backlog
**References**: [`testing-strategy.md`](testing-strategy.md#performance-testing) ⭐ CRITICAL, [`architecture.md`](architecture.md#chunk-volume-guidance)
**Tasks**:
- Load larger test dataset (50K-100K invoices)
- Measure throughput (conversions per hour)
- Measure chunk duration
- Identify bottlenecks
- Tune chunk size if needed

#### Story 4.7: Idempotency Testing
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`architecture.md`](architecture.md#idempotency-rules), [`worker-processing.md`](worker-processing.md#idempotency-rules), [`planner-and-chunking.md`](planner-and-chunking.md#uniqueness-rule)
**Tasks**:
- Rerun planner on same month (verify no duplicates)
- Requeue completed chunks (verify skips already successful)
- Test partial chunk retry
- Verify no duplicate PDFs

---

## Epic 5: Hardening & Production Prep (Month 4-5)

**Goal**: Harden the system, complete documentation, run rehearsal test, prepare for production

**Acceptance Criteria**:
- [ ] One-month rehearsal test completed successfully
- [ ] All documentation complete
- [ ] Runbooks tested
- [ ] Operations team trained
- [ ] Production readiness review passed

### Stories

#### Story 5.1: Error Handling Improvements
**Owner**: Tyler & Riyanshi | **Effort**: 3 days | **Status**: Backlog
**References**: [`failure-handling.md`](failure-handling.md) ⭐ CRITICAL, [`conversion-results.md`](conversion-results.md#result-statuses)
**Tasks**:
- Add comprehensive error handling throughout
- Improve error messages and logging
- Add structured failure codes
- Test all error paths

#### Story 5.2: Retry Logic Hardening
**Owner**: Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`architecture.md`](architecture.md#lease-validations), [`failure-handling.md`](failure-handling.md#failure-classification)
**Tasks**:
- Implement exponential backoff for all retries
- Add jitter to prevent thundering herd
- Add max retry limits
- Test retry behavior

#### Story 5.3: Configuration Validation
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`routing-rules.md`](routing-rules.md#validation-rules), [`deployment-guide.md`](deployment-guide.md#step-11-verification)
**Tasks**:
- Add config file validation at startup
- Validate routing rules syntax
- Validate BigQuery schema matches expectations
- Validate bucket permissions

#### Story 5.4: Logging Improvements
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`runbook.md`](runbook.md#log-locations), [`worker-processing.md`](worker-processing.md#logging)
**Tasks**:
- Standardize log format (structured JSON)
- Add correlation IDs (chunk_id, worker_id)
- Add timing information
- Configure log levels

#### Story 5.5: One-Month Rehearsal Test
**Owner**: Tyler & Riyanshi | **Effort**: 5 days | **Status**: Backlog
**Dependencies**: All previous stories
**References**: [`testing-strategy.md`](testing-strategy.md#one-month-rehearsal-test) ⭐ CRITICAL, [`architecture.md`](architecture.md#acceptance-criteria-for-this-architecture)
**Tasks**:
- Prepare production-like test data (1 full month)
- Run planner and workers
- Monitor continuously for 3-4 days
- Measure throughput and success rate
- Document results and issues
- Fix any critical issues found

#### Story 5.6: Runbook Testing
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`runbook.md`](runbook.md) ⭐ CRITICAL
**Tasks**:
- Walk through all runbook procedures
- Test start/stop workers
- Test requeue failed chunks
- Test replay a month
- Update runbook based on findings

#### Story 5.7: Operations Training
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`runbook.md`](runbook.md), [`failure-handling.md`](failure-handling.md), [`diagrams/reporting_progress_diagram.md`](diagrams/reporting_progress_diagram.md)
**Tasks**:
- Train operations team on system
- Walk through monitoring dashboards
- Walk through common troubleshooting
- Provide hands-on practice
- Answer questions

#### Story 5.8: Production Readiness Review
**Owner**: Tyler & Riyanshi | **Effort**: 2 days | **Status**: Backlog
**References**: [`testing-strategy.md`](testing-strategy.md#acceptance-criteria-for-production-readiness) ⭐ CRITICAL, [`architecture.md`](architecture.md#acceptance-criteria-for-this-architecture)
**Tasks**:
- Review all acceptance criteria from testing-strategy.md
- Complete production readiness checklist
- Document any known issues or limitations
- Get sign-off from stakeholders

#### Story 5.9: Production Deployment
**Owner**: Tyler & Riyanshi | **Effort**: 3 days | **Status**: Backlog
**References**: [`deployment-guide.md`](deployment-guide.md) ⭐ CRITICAL, [`runbook.md`](runbook.md), [`failure-handling.md`](failure-handling.md)
**Tasks**:
- Deploy to production environment
- Verify all components working
- Upload first production month
- Monitor closely for first 24 hours
- Be ready for on-call support

---

## Kanban Board Columns

### Backlog
Stories not yet started, prioritized top to bottom

### In Progress
Stories currently being worked on (limit: 2 per developer)
- Tyler: max 2 stories
- Riyanshi: max 2 stories

### Review
Stories complete and awaiting review/testing

### Done
Stories completed and verified

---

## Dependencies Summary

**Critical Path**:
1. Epic 1 (Foundation) → Epic 2 (Planner) → Epic 3 (Worker) → Epic 4 (Integration) → Epic 5 (Production)

**Parallel Work Opportunities**:
- Tyler can work on Planner (Epic 2) while Riyanshi works on Worker (Epic 3)
- Terraform (Story 1.8) can be done in parallel with other Month 1 work
- Monitoring (Story 4.4) can be set up while testing is ongoing

**Blocking Dependencies**:
- Workers cannot be fully tested until Planner is complete
- Integration testing requires both Planner and Worker complete
- Rehearsal test requires all previous epics complete

---

## Risk Management

### Top Risks

1. **Converter Integration Issues**
   - Mitigation: Test converter early (Month 1)
   - Contingency: Have vendor support contact ready

2. **Performance Not Meeting Target**
   - Mitigation: Performance test in Month 3
   - Contingency: Add more workers or optimize chunk size

3. **Data Quality Issues**
   - Mitigation: Test with representative data early
   - Contingency: Add more validation and error handling

4. **Scope Creep**
   - Mitigation: Stick to documented requirements
   - Contingency: Defer non-critical features to v2

## Related Documents

- [`architecture.md`](architecture.md): System architecture and design
- [`testing-strategy.md`](testing-strategy.md): Testing approach and acceptance criteria
- [`deployment-guide.md`](deployment-guide.md): Deployment procedures
- [`runbook.md`](runbook.md): Operational procedures