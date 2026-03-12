# GCP Batch ETL Pipeline (Mock, Production‑Style)

A production‑style **batch ETL** pipeline that simulates a **mainframe → cloud** workflow on **Google Cloud Platform (GCP)**.

The pipeline models how enterprise invoice data is delivered, processed, stored, and indexed using Linux, Unix tooling, and cloud‑native services.

---

## Overview

This project simulates a realistic enterprise data pipeline where:

- A **mainframe** generates invoice data in **AFP (Advanced Function Presentation)** format.
- Files are packaged into **TAR batches** and delivered via **SFTP**.
- A **Linux VM** ingests, processes, and converts documents (**AFP → PDF**).
- Files are stored in **Google Cloud Storage (GCS)**.
- **Metadata** is published to **BigQuery** for analytics and lookup.

The goal is to practice and demonstrate:
- Linux‑based data processing
- Unix shell scripting
- Batch ETL design
- Cloud storage patterns
- Clear separation of responsibilities across systems

## Development Resources

- **Processed PDFs (GCS bucket):** `gs://afp-pdfs-dev-highttyler`