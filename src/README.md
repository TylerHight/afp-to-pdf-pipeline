# Source Code (Production Application)

This directory contains the core application code that runs autonomously on the fleet of worker VMs.

## Components

* **`processing/`**
  Contains the low-level logic for handling files.
  * `run_etl_pipeline.sh`: The master orchestration script that outlines the lifecycle of a single batch (download, extract, convert, upload, archive).
  
* **`worker/`** *(Planned)*
  The distributed workload management logic. Will contain the Python daemon responsible for claiming BigQuery lock rows, renewing leases, and handling retry or failure logic.

* **`bigquery/`**
  The BigQuery lock-table client module. Contains reusable Python functions and shell wrappers for seeding shards, claiming work, heartbeating active leases, and marking work complete or failed.

* **`main.py`**
  The entry point for the worker daemon. Starts the lock-claim loop and initializes the application.
