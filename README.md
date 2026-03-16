# AFP to PDF Invoice Pipeline

This repository contains the code and infrastructure configuration for a mainframe-to-cloud batch ETL pipeline. The pipeline is designed to process monthly customer internet invoices, transforming legacy AFP (Advanced Function Presentation) files into standard PDFs, and loading metadata into Google Cloud BigQuery.

## Architecture Overview

The system is designed to run across a fleet of Linux VMs in a distributed manner:
1. **Ingestion:** AFP payloads are aggregated into TAR files and uploaded to Google Cloud Storage (GCS) `Raw`.
2. **Workload Distribution:** A Google Cloud Pub/Sub queue distributes batches to available worker VMs to prevent bottlenecks and ensure fault tolerance.
3. **Processing:** Worker VMs download the batches, extract them, and utilize a vendor tool to convert AFP files to PDFs.
4. **Storage & Metadata:** Generated PDFs are uploaded to a GCS `Processed` bucket. Processing metadata is published to a BigQuery data warehouse for analytics and reporting.

## Repository Structure

To maintain a clean separation of concerns, the repository is organized into domains:

```text
afp-to-pdf-pipeline/
├── infrastructure/    # Cloud provisioning (Terraform, VM startup scripts)
├── scripts/           # Ad-hoc admin, reporting, setup, and dev data tools
├── src/               # Core production application code running on the VMs
└── tests/             # Automated unit and integration tests
```

> **Note:** See the nested `README.md` files within `src/` and `scripts/` for detailed explanations of those specific directories.

## Tech Stack

* **Operating System:** Linux (Ubuntu/Debian)
* **Orchestration:** Bash shell scripting & Python
* **Cloud Provider:** Google Cloud Platform (GCP)
  * **Storage:** Cloud Storage (GCS)
  * **Messaging:** Cloud Pub/Sub
  * **Analytics:** BigQuery

## Getting Started

*(Instructions to be added for local development setup, credentials, and deployment).*

### Prerequisites
* `gcloud` CLI installed and authenticated
* Python 3.x
* Vendor `afp2pdf` binary available on the host system

## Current Status

- [x] Bash scaffolding for the ETL lifecycle (`src/run_etl_pipeline.sh`).
- [x] Utilities for generating mock dev data and coverage reporting (`scripts/`).
- [ ] Migration of the core worker daemon to Python.
- [ ] Implementation of the Pub/Sub listener.
- [ ] BigQuery metadata insertion logic.