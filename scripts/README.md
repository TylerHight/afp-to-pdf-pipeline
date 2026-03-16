# Utility Scripts

This directory contains ad-hoc shell and Python scripts used for administration, reporting, setup, and local development. 

**Important:** The scripts in this directory are *not* intended to be run by the core worker daemon on the production VMs. Core pipeline logic belongs in the `src/` directory.

## Directory Layout

* **`mock_data/`** 
  Tools to seed realistic development and test datasets.
  *Example: `generate_test_invoices.sh` populates a GCS bucket with dummy invoice configurations.*

* **`reporting/`** 
  Scripts to monitor the health and completeness of the processed data.
  *Example: `report_monthly_coverage.sh` scans the processed bucket to identify existing and missing Billing Account Numbers (BANs) within a date range.*

* **`setup/`** *(Planned)*
  One-time initialization scripts to scaffold cloud infrastructure, such as creating Pub/Sub topics/subscriptions or defining BigQuery schemas.

* **`admin/`** *(Planned)*
  Scripts for manual operational tasks, such as querying BigQuery directly via Python from an administrator's machine.

* **`deployment/`** *(Planned)*
  Scripts to package the `src/` directory and deploy it to the fleet of worker VMs.