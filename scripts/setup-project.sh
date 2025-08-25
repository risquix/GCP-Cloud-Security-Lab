#!/bin/bash
# GCP Cloud Security Lab - Project Setup
# Project ID: clgcporg10-173

set -e

PROJECT_ID="clgcporg10-173"
REGION="us-central1"
ZONE="us-central1-c"

echo "=== Setting up GCP Cloud Security Lab ==="
echo "Project ID: $PROJECT_ID"
echo "Zone: $ZONE"

# Set the project
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

# Enable required APIs
echo "Enabling required APIs..."
gcloud services enable \
    compute.googleapis.com \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    cloudkms.googleapis.com \
    binaryauthorization.googleapis.com \
    containerscanning.googleapis.com \
    securitycenter.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    aiplatform.googleapis.com \
    networkservices.googleapis.com \
    certificatemanager.googleapis.com \
    dns.googleapis.com

# Create Artifact Registry repository
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create wizknowledge \
    --repository-format=docker \
    --location=$REGION \
    --description="WizKnowledge container images" || true

# Create service accounts
echo "Creating service accounts..."
gcloud iam service-accounts create dev-workload-sa \
    --display-name="Dev Workload Service Account" || true

gcloud iam service-accounts create prod-workload-sa \
    --display-name="Prod Workload Service Account" || true

gcloud iam service-accounts create github-actions-sa \
    --display-name="GitHub Actions CI/CD" || true

# Grant permissions (Dev - intentionally over-privileged)
echo "Configuring IAM permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:dev-workload-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/editor" || true

# Prod - least privilege
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:prod-workload-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter" || true

# Create Terraform state bucket
echo "Creating Terraform state bucket..."
gsutil mb -p $PROJECT_ID -l $REGION gs://${PROJECT_ID}-terraform-state || true
gsutil versioning set on gs://${PROJECT_ID}-terraform-state || true

echo "=== Project setup complete ==="
