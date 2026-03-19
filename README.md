# AFP to PDF Invoice Pipeline

This repository contains the code and infrastructure configuration for a mainframe-to-cloud batch ETL pipeline. The pipeline is designed to process monthly customer internet invoices, transforming legacy AFP (Advanced Function Presentation) files into standard PDFs, and coordinating worker load through a BigQuery lock table.

See [docs/architecture.md](docs/architecture.md) for the full pipeline architecture, delivery plan, validations, and operational guidance. Companion docs:

- [docs/planner-and-chunking.md](docs/planner-and-chunking.md)
- [docs/conversion-results.md](docs/conversion-results.md)

## Architecture Overview

The system is designed to run across a fleet of Linux VMs in a distributed manner:
1. **Ingestion:** AFP payloads are aggregated into TAR files and uploaded to an input GCS bucket.
2. **Workload Distribution:** A BigQuery `work_locks` table holds shard rows that worker VMs lease, heartbeat, complete, or fail.
3. **Processing:** Worker VMs download the assigned TAR payload, extract it, and use a vendor tool to convert AFP files to PDFs.
4. **Storage:** Generated PDFs are uploaded to a destination GCS bucket, and the lock row preserves lease and retry state.

For a 12-VM fleet, the lock table should contain more shards than VMs so load stays balanced. A practical pattern is one row per tar file or one row per 1 to 3 invoice days with a precomputed BAN list, with at least 5 to 10 times as many rows as workers.

## Repository Structure

To maintain a clean separation of concerns, the repository is organized into domains:

```text
afp-to-pdf-pipeline/
|-- infrastructure/    # Cloud provisioning (Terraform, VM startup scripts)
|-- scripts/           # Ad-hoc admin, reporting, setup, and dev data tools
|-- src/               # Core production application code running on the VMs
`-- tests/             # Automated unit and integration tests
```

> **Note:** See the nested `README.md` files within `src/` and `scripts/` for detailed explanations of those specific directories.

## Tech Stack

* **Operating System:** Linux (Ubuntu/Debian)
* **Orchestration:** Bash shell scripting and Python
* **Cloud Provider:** Google Cloud Platform (GCP)
  * **Storage:** Cloud Storage (GCS)
  * **Work Distribution:** BigQuery lock table
  * **Analytics / Coordination:** BigQuery

## Getting Started

*(Instructions to be added for local development setup, credentials, and deployment).*

### Prerequisites
* `gcloud` CLI installed and authenticated
* Python 3.x
* Vendor `afp2pdf` binary available on the host system

## Current Status

- [x] Bash scaffolding for the ETL lifecycle (`src/run_etl_pipeline.sh`).
- [x] Utilities for generating mock dev data and coverage reporting (`scripts/`).
- [x] BigQuery lock-table schema and lease utility (`src/bigquery/`).
- [ ] Migration of the core worker daemon to Python.
- [ ] Implementation of the worker daemon that claims and renews BigQuery leases.
- [ ] Seeding logic for creating shard rows from incoming TAR manifests.
