# Source Code (Production Application)

This directory contains the core application code that runs autonomously on the fleet of worker VMs. 

## Components

* **`processing/`**
  Contains the low-level logic for handling files.
  * `run_etl_pipeline.sh`: The master orchestration script that outlines the lifecycle of a single batch (download, extract, convert, upload, archive).
  
* **`worker/`** *(Planned)*
  The distributed workload management logic. Will contain the Python daemon responsible for listening to Google Cloud Pub/Sub, claiming tasks, and handling retry/failure logic.

* **`bigquery/`** *(Planned)*
  The BigQuery client module. Contains reusable Python functions for inserting pipeline execution metadata into the data warehouse securely and efficiently.

* **`main.py`**
  The entry point for the worker daemon. Starts the Pub/Sub listener and initializes the application.