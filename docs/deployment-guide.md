# Deployment and Environment Setup Guide

## Purpose

This document provides step-by-step instructions for deploying the AFP-to-PDF pipeline infrastructure and application components.

It covers VM setup, service accounts, credentials, Python dependencies, converter installation, systemd service configuration, and Terraform apply order.

## Scope

This document covers:

- prerequisites and requirements
- GCP project setup
- service account creation and IAM configuration
- GCS bucket creation
- BigQuery dataset and table creation
- VM provisioning and configuration
- Python environment setup
- AFP converter installation
- systemd service configuration
- Terraform deployment order
- verification and testing

This document does not cover:

- ongoing operations (see runbook.md)
- failure recovery (see failure-handling.md)
- architecture decisions (see architecture.md)

## Prerequisites

### Required Tools

- **Terraform**: v1.0 or later
- **gcloud CLI**: Latest version
- **Python**: 3.9 or later (for local testing)
- **Git**: For cloning repository
- **SSH**: For VM access

### Required Access

- **GCP Project**: Owner or Editor role
- **Service Account Admin**: To create service accounts
- **Compute Admin**: To create VMs
- **Storage Admin**: To create buckets
- **BigQuery Admin**: To create datasets and tables

### Required Information

- **GCP Project ID**: e.g., `afp-pipeline-prod`
- **Region**: e.g., `us-central1`
- **Zone**: e.g., `us-central1-a`
- **AFP Converter License**: License key for converter software
- **Source Data Location**: Where tar files will be uploaded

## Deployment Overview

### Deployment Order

1. Configure GCP project and enable APIs
2. Create service accounts
3. Create VPC network and subnets
4. Create Cloud NAT
5. Create GCS buckets
6. Create BigQuery dataset and tables
7. Create controller VM
8. Create worker VMs
9. Deploy application code
10. Configure systemd services
11. Verify deployment

### Estimated Time

- Infrastructure setup: 30-60 minutes
- Application deployment: 30-45 minutes
- Testing and verification: 30 minutes
- **Total**: 1.5-2.5 hours

## Step 1: GCP Project Setup

### Create or Select Project

```bash
# Set project ID
export PROJECT_ID="afp-pipeline-prod"
export REGION="us-central1"
export ZONE="us-central1-a"

# Create new project (if needed)
gcloud projects create $PROJECT_ID --name="AFP to PDF Pipeline"

# Set default project
gcloud config set project $PROJECT_ID

# Link billing account (replace with your billing account ID)
gcloud beta billing projects link $PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX
```

### Enable Required APIs

```bash
# Enable required GCP APIs
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

## Step 2: Service Account Creation

### Create Service Accounts

```bash
# Planner service account
gcloud iam service-accounts create afp-planner \
  --display-name="AFP Planner Service Account" \
  --description="Used by controller VM to run planner job"

# Worker service account
gcloud iam service-accounts create afp-worker \
  --display-name="AFP Worker Service Account" \
  --description="Used by worker VMs to process chunks"

# Admin service account
gcloud iam service-accounts create afp-admin \
  --display-name="AFP Admin Service Account" \
  --description="Used by operations team for administrative tasks"
```

### Grant IAM Roles

```bash
# Planner SA permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:afp-planner@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

# Worker SA permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:afp-worker@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

# Note: Bucket and BigQuery permissions will be granted after resources are created
```

## Step 3: Network Setup

### Create VPC Network

```bash
# Create VPC network
gcloud compute networks create afp-pipeline-vpc \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

# Create subnet
gcloud compute networks subnets create afp-subnet-us-central1 \
  --network=afp-pipeline-vpc \
  --region=$REGION \
  --range=10.0.0.0/24
```

### Create Cloud NAT

```bash
# Create Cloud Router
gcloud compute routers create afp-router \
  --network=afp-pipeline-vpc \
  --region=$REGION

# Create Cloud NAT
gcloud compute routers nats create afp-nat \
  --router=afp-router \
  --region=$REGION \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges
```

### Create Firewall Rules

```bash
# Allow SSH from IAP
gcloud compute firewall-rules create allow-ssh-from-iap \
  --network=afp-pipeline-vpc \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --description="Allow SSH from Identity-Aware Proxy"

# Allow internal communication
gcloud compute firewall-rules create allow-internal \
  --network=afp-pipeline-vpc \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/24 \
  --description="Allow internal communication between VMs"
```

## Step 4: GCS Bucket Creation

### Create Buckets

```bash
# Input bucket
gsutil mb -l $REGION gs://afp-input-${PROJECT_ID}

# Output buckets
gsutil mb -l $REGION gs://afp-output-residential-${PROJECT_ID}
gsutil mb -l $REGION gs://afp-output-business-${PROJECT_ID}
gsutil mb -l $REGION gs://afp-output-archive-${PROJECT_ID}
```

### Set Bucket Permissions

```bash
# Planner SA: read input bucket, write manifests
gsutil iam ch \
  serviceAccount:afp-planner@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectViewer \
  gs://afp-input-${PROJECT_ID}

gsutil iam ch \
  serviceAccount:afp-planner@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectCreator \
  gs://afp-input-${PROJECT_ID}

# Worker SA: read input bucket
gsutil iam ch \
  serviceAccount:afp-worker@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectViewer \
  gs://afp-input-${PROJECT_ID}

# Worker SA: write output buckets
for bucket in residential business archive; do
  gsutil iam ch \
    serviceAccount:afp-worker@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectCreator \
    gs://afp-output-${bucket}-${PROJECT_ID}
done
```

### Set Lifecycle Policies

```bash
# Create lifecycle policy for input bucket
cat > /tmp/input-lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/input-lifecycle.json gs://afp-input-${PROJECT_ID}

# Create lifecycle policy for output buckets
cat > /tmp/output-lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF

for bucket in residential business archive; do
  gsutil lifecycle set /tmp/output-lifecycle.json gs://afp-output-${bucket}-${PROJECT_ID}
done
```

## Step 5: BigQuery Setup

### Create Dataset

```bash
bq mk --location=$REGION --dataset ${PROJECT_ID}:afp_pipeline
```

### Create Tables

```bash
# Create work_locks table
bq mk --table \
  ${PROJECT_ID}:afp_pipeline.work_locks \
  lock_id:STRING,shard_key:STRING,date_range_start:DATE,date_range_end:DATE,target_ban_count:INTEGER,selected_ban_count:INTEGER,chunk_index:INTEGER,ban_list_uri:STRING,priority:INTEGER,status:STRING,worker_id:STRING,lease_token:STRING,lease_expires_at:TIMESTAMP,attempt_count:INTEGER,max_attempts:INTEGER,metadata_json:STRING,created_at:TIMESTAMP,updated_at:TIMESTAMP,completed_at:TIMESTAMP

# Create conversion_results table
bq mk --table \
  ${PROJECT_ID}:afp_pipeline.conversion_results \
  result_id:STRING,lock_id:STRING,shard_key:STRING,planning_run_id:STRING,processing_month:STRING,statement_date:DATE,ban:STRING,source_tar_uri:STRING,source_member_path:STRING,destination_uri:STRING,worker_id:STRING,attempt_number:INTEGER,result_status:STRING,failure_code:STRING,failure_message:STRING,converter_exit_code:INTEGER,output_bytes:INTEGER,output_sha256:STRING,started_at:TIMESTAMP,completed_at:TIMESTAMP,inserted_at:TIMESTAMP
```

### Set Table Partitioning and Clustering

```bash
# Update work_locks table
bq update --time_partitioning_field=created_at \
  --clustering_fields=status,priority,date_range_start \
  ${PROJECT_ID}:afp_pipeline.work_locks

# Update conversion_results table
bq update --time_partitioning_field=inserted_at \
  --clustering_fields=processing_month,result_status,worker_id,shard_key \
  ${PROJECT_ID}:afp_pipeline.conversion_results
```

### Create Views

See [`bigquery-schema.md`](bigquery-schema.md) for view definitions. Create views using:

```bash
# Create vw_month_progress
bq mk --use_legacy_sql=false --view='<SQL from bigquery-schema.md>' \
  ${PROJECT_ID}:afp_pipeline.vw_month_progress

# Create vw_chunk_progress
bq mk --use_legacy_sql=false --view='<SQL from bigquery-schema.md>' \
  ${PROJECT_ID}:afp_pipeline.vw_chunk_progress

# Create vw_worker_throughput
bq mk --use_legacy_sql=false --view='<SQL from bigquery-schema.md>' \
  ${PROJECT_ID}:afp_pipeline.vw_worker_throughput

# Create vw_stale_and_retried_chunks
bq mk --use_legacy_sql=false --view='<SQL from bigquery-schema.md>' \
  ${PROJECT_ID}:afp_pipeline.vw_stale_and_retried_chunks
```

### Grant BigQuery Permissions

```bash
# Planner SA: write work_locks
bq add-iam-policy-binding \
  --member="serviceAccount:afp-planner@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" \
  ${PROJECT_ID}:afp_pipeline

# Worker SA: read/write work_locks, write conversion_results
bq add-iam-policy-binding \
  --member="serviceAccount:afp-worker@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" \
  ${PROJECT_ID}:afp_pipeline

# Admin SA: full access
bq add-iam-policy-binding \
  --member="serviceAccount:afp-admin@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin" \
  ${PROJECT_ID}:afp_pipeline
```

## Step 6: VM Creation

### Create Controller VM

```bash
# Create startup script
cat > /tmp/controller-startup.sh <<'EOF'
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Python and dependencies
apt-get install -y python3.9 python3-pip git

# Create application directory
mkdir -p /opt/afp-pipeline
chown -R root:root /opt/afp-pipeline

# Install Python packages
pip3 install google-cloud-storage google-cloud-bigquery

# Log completion
echo "Controller VM setup complete" | tee -a /var/log/startup-script.log
EOF

# Create controller VM
gcloud compute instances create afp-controller-01 \
  --zone=$ZONE \
  --machine-type=n1-standard-2 \
  --subnet=afp-subnet-us-central1 \
  --no-address \
  --service-account=afp-planner@${PROJECT_ID}.iam.gserviceaccount.com \
  --scopes=cloud-platform \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-standard \
  --metadata-from-file=startup-script=/tmp/controller-startup.sh \
  --tags=afp-controller
```

### Create Worker VMs

```bash
# Create worker startup script
cat > /tmp/worker-startup.sh <<'EOF'
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Python and dependencies
apt-get install -y python3.9 python3-pip git tar

# Create application directory
mkdir -p /opt/afp-pipeline
chown -R root:root /opt/afp-pipeline

# Install Python packages
pip3 install google-cloud-storage google-cloud-bigquery

# Create working directory for tar extraction
mkdir -p /var/lib/afp-worker/temp
chown -R root:root /var/lib/afp-worker

# Log completion
echo "Worker VM setup complete" | tee -a /var/log/startup-script.log
EOF

# Create worker VMs (12 total)
for i in $(seq -f "%02g" 1 12); do
  gcloud compute instances create afp-worker-${i} \
    --zone=$ZONE \
    --machine-type=n1-standard-4 \
    --subnet=afp-subnet-us-central1 \
    --no-address \
    --service-account=afp-worker@${PROJECT_ID}.iam.gserviceaccount.com \
    --scopes=cloud-platform \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-standard \
    --metadata-from-file=startup-script=/tmp/worker-startup.sh \
    --tags=afp-worker &
done

# Wait for all VMs to be created
wait
```

## Step 7: Application Deployment

### Clone Repository

```bash
# Clone repository to local machine
git clone https://github.com/your-org/afp-to-pdf-pipeline.git
cd afp-to-pdf-pipeline
```

### Deploy to Controller VM

```bash
# Copy application code to controller VM
gcloud compute scp --recurse \
  --zone=$ZONE \
  ./src/planner \
  afp-controller-01:/opt/afp-pipeline/

# Copy configuration
gcloud compute scp --zone=$ZONE \
  ./config/planner-config.yaml \
  afp-controller-01:/opt/afp-pipeline/config/

# SSH to controller and set up cron job
gcloud compute ssh afp-controller-01 --zone=$ZONE --command='
  # Create cron job for planner
  echo "0 2 * * * /usr/bin/python3 /opt/afp-pipeline/planner/run_planner.py >> /var/log/afp-planner.log 2>&1" | crontab -
'
```

### Deploy to Worker VMs

```bash
# Deploy to all worker VMs
for i in $(seq -f "%02g" 1 12); do
  # Copy application code
  gcloud compute scp --recurse \
    --zone=$ZONE \
    ./src/worker \
    afp-worker-${i}:/opt/afp-pipeline/

  # Copy configuration
  gcloud compute scp --zone=$ZONE \
    ./config/routing-rules.yaml \
    afp-worker-${i}:/opt/afp-pipeline/config/
done
```

## Step 8: AFP Converter Installation

### Install Converter on Worker VMs

```bash
# Assuming converter is provided as a .tar.gz or .deb package
# Adjust based on actual converter distribution format

for i in $(seq -f "%02g" 1 12); do
  gcloud compute ssh afp-worker-${i} --zone=$ZONE --command='
    # Create converter directory
    sudo mkdir -p /opt/afp-converter

    # Download converter (adjust URL)
    # wget -O /tmp/afp-converter.tar.gz https://vendor.com/afp-converter.tar.gz

    # Extract converter
    # sudo tar -xzf /tmp/afp-converter.tar.gz -C /opt/afp-converter

    # Set permissions
    sudo chmod +x /opt/afp-converter/bin/afp2pdf

    # Install license
    # sudo cp /path/to/license.key /opt/afp-converter/license/

    # Test converter
    /opt/afp-converter/bin/afp2pdf --version
  '
done
```

## Step 9: Systemd Service Configuration

### Create Planner Service

```bash
# Create planner service file
cat > /tmp/afp-planner.service <<'EOF'
[Unit]
Description=AFP to PDF Planner Service
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/afp-pipeline/planner
ExecStart=/usr/bin/python3 /opt/afp-pipeline/planner/run_planner.py
StandardOutput=journal
StandardError=journal
SyslogIdentifier=afp-planner

[Install]
WantedBy=multi-user.target
EOF

# Copy to controller VM
gcloud compute scp --zone=$ZONE \
  /tmp/afp-planner.service \
  afp-controller-01:/tmp/

# Install service
gcloud compute ssh afp-controller-01 --zone=$ZONE --command='
  sudo mv /tmp/afp-planner.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable afp-planner.service
'
```

### Create Worker Service

```bash
# Create worker service file
cat > /tmp/afp-worker.service <<'EOF'
[Unit]
Description=AFP to PDF Worker Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/afp-pipeline/worker
ExecStart=/usr/bin/python3 /opt/afp-pipeline/worker/run_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=afp-worker

[Install]
WantedBy=multi-user.target
EOF

# Deploy to all worker VMs
for i in $(seq -f "%02g" 1 12); do
  # Copy service file
  gcloud compute scp --zone=$ZONE \
    /tmp/afp-worker.service \
    afp-worker-${i}:/tmp/

  # Install and start service
  gcloud compute ssh afp-worker-${i} --zone=$ZONE --command='
    sudo mv /tmp/afp-worker.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable afp-worker.service
    sudo systemctl start afp-worker.service
  '
done
```

## Step 10: Terraform Deployment (Alternative)

### Terraform Structure

```
infrastructure/terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── modules/
    ├── service_account/
    ├── storage_bucket/
    ├── bigquery/
    └── compute_instance/
```

### Terraform Apply Order

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply in stages for better control
# Stage 1: Service accounts and IAM
terraform apply -target=module.service_accounts

# Stage 2: Network
terraform apply -target=module.network

# Stage 3: Storage
terraform apply -target=module.storage_buckets

# Stage 4: BigQuery
terraform apply -target=module.bigquery

# Stage 5: Compute
terraform apply -target=module.controller_vm
terraform apply -target=module.worker_vms

# Or apply all at once
terraform apply tfplan
```

## Step 11: Verification

### Verify Infrastructure

```bash
# Check VMs are running
gcloud compute instances list --filter="name~afp-"

# Check buckets exist
gsutil ls | grep afp-

# Check BigQuery dataset
bq ls ${PROJECT_ID}:afp_pipeline

# Check service accounts
gcloud iam service-accounts list | grep afp-
```

### Verify Application

```bash
# Check controller VM
gcloud compute ssh afp-controller-01 --zone=$ZONE --command='
  python3 --version
  ls -la /opt/afp-pipeline/planner
  crontab -l
'

# Check worker VMs
for i in $(seq -f "%02g" 1 12); do
  echo "Checking afp-worker-${i}..."
  gcloud compute ssh afp-worker-${i} --zone=$ZONE --command='
    python3 --version
    ls -la /opt/afp-pipeline/worker
    sudo systemctl status afp-worker
    /opt/afp-converter/bin/afp2pdf --version
  '
done
```

### Verify Connectivity

```bash
# Test GCS access from worker
gcloud compute ssh afp-worker-01 --zone=$ZONE --command='
  gsutil ls gs://afp-input-'${PROJECT_ID}'
  echo "test" > /tmp/test.txt
  gsutil cp /tmp/test.txt gs://afp-output-residential-'${PROJECT_ID}'/test/
  gsutil rm gs://afp-output-residential-'${PROJECT_ID}'/test/test.txt
'

# Test BigQuery access from worker
gcloud compute ssh afp-worker-01 --zone=$ZONE --command='
  bq ls '${PROJECT_ID}':afp_pipeline
'
```

## Step 12: Initial Testing

### Upload Test Data

```bash
# Create test tar file
tar -czf /tmp/test-2026-03-01.tar test-data/

# Upload to input bucket
gsutil cp /tmp/test-2026-03-01.tar gs://afp-input-${PROJECT_ID}/monthly/2026-03/
```

### Run Planner Manually

```bash
gcloud compute ssh afp-controller-01 --zone=$ZONE --command='
  cd /opt/afp-pipeline/planner
  python3 run_planner.py --month 2026-03
'
```

### Verify Chunks Created

```bash
# Check manifests
gsutil ls gs://afp-input-${PROJECT_ID}/manifests/2026-03/

# Check work_locks
bq query --use_legacy_sql=false '
SELECT COUNT(*) as chunk_count, status
FROM `'${PROJECT_ID}'.afp_pipeline.work_locks`
GROUP BY status
'
```

### Monitor Workers

```bash
# Check worker logs
for i in $(seq -f "%02g" 1 3); do
  echo "=== Worker ${i} ==="
  gcloud compute ssh afp-worker-${i} --zone=$ZONE --command='
    sudo journalctl -u afp-worker -n 20
  '
done
```

## Troubleshooting

### VMs Not Starting

- Check startup script logs: `gcloud compute instances get-serial-port-output <vm-name>`
- Check quotas: Ensure sufficient CPU and disk quotas
- Check service account permissions

### Workers Not Claiming Chunks

- Check BigQuery permissions
- Check work_locks table has PENDING chunks
- Check worker logs for errors
- Verify network connectivity

### Converter Not Working

- Check converter installation path
- Check license file
- Test converter manually
- Check converter logs

## Post-Deployment Tasks

1. **Set Up Monitoring**: Configure Cloud Monitoring dashboards and alerts
2. **Set Up Logging**: Configure log exports and retention
3. **Document Credentials**: Store service account keys securely
4. **Create Runbooks**: Document operational procedures
5. **Train Team**: Train operations team on system

## Related Documents

- [`architecture.md`](architecture.md): System architecture
- [`runbook.md`](runbook.md): Operational procedures
- [`bigquery-schema.md`](bigquery-schema.md): Table schemas
- [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md): Deployment topology
- Terraform modules: `infrastructure/terraform/`