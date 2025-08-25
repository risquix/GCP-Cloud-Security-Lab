# GCP Cloud Security Lab

## Overview
This repository demonstrates a comprehensive cloud security implementation on Google Cloud Platform, featuring intentionally vulnerable development environments and secured production environments.

### Architecture
- **Application**: WizKnowledge - AI-powered Q&A system with RAG
- **Database**: MongoDB (3.2 vulnerable / 7.0 secure)
- **Kubernetes**: GKE clusters (dev vulnerable / prod hardened)
- **Storage**: GCS buckets (public dev / private encrypted prod)

### Project Details
- **GCP Project ID**: clgcporg10-173
- **Region**: us-central1
- **Zone**: us-central1-c

## Quick Start

1. **Setup Project**
```bash
./scripts/setup-project.sh
```

2. **Deploy Infrastructure**
```bash
cd terraform
terraform init
terraform apply
```

3. **Build and Deploy Applications**
```bash
./scripts/build-and-deploy.sh
```

## Environments

### Development (Vulnerable)
- 18 critical security vulnerabilities
- Public MongoDB access
- Root containers
- Excessive IAM permissions
- Public GCS bucket

### Production (Secure)
- Binary Authorization
- Workload Identity
- Network Policies
- Encrypted storage
- Private endpoints only

## Security Findings
- **Dev Environment**: 57 total vulnerabilities
- **Prod Environment**: 7 informational findings
- **Detection Time**: < 2 minutes
- **Compliance Score**: Dev 45% → Prod 98%

## Documentation
See the `docs/` directory for detailed documentation.
