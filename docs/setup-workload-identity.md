# Workload Identity Federation Setup Guide

This guide walks you through configuring Google Cloud Workload Identity Federation to allow GitHub Actions to authenticate with GCP without using static service account keys.

## Prerequisites

- Google Cloud project with billing enabled
- `gcloud` CLI installed locally
- Owner or IAM Admin role in the GCP project
- GitHub repository where workflows will run

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   GitHub Actions                        │
│              (OIDC Token from GitHub)                   │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ OIDC Token Exchange
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│         GCP Workload Identity Pool                      │
│    ┌─────────────────────────────────────┐              │
│    │   Workload Identity Provider        │              │
│    │   (GitHub OIDC configured)          │              │
│    └─────────────────────────────────────┘              │
│                         │                               │
│                         │ Token Exchange                │
│                         ▼                               │
│    ┌─────────────────────────────────────┐              │
│    │   Service Account                   │              │
│    │   (GCR push permissions)            │              │
│    └─────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

## Step-by-Step Setup

### 1. Enable Required APIs

```bash
# Set your project ID
export PROJECT_ID="your-gcp-project-id"
gcloud config set project $PROJECT_ID

# Enable necessary APIs
gcloud services enable iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    containerregistry.googleapis.com \
    artifactregistry.googleapis.com
```

### 2. Create Workload Identity Pool

```bash
# Create the pool
gcloud iam workload-identity-pools create "github-pool" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="GitHub Actions Pool"

# Get the pool ID (save this for later)
gcloud iam workload-identity-pools describe "github-pool" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --format="value(name)"
```

### 3. Create Workload Identity Provider

```bash
# Create OIDC provider for GitHub
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --display-name="GitHub Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --issuer-uri="https://token.actions.githubusercontent.com"

# Get the provider resource name
gcloud iam workload-identity-pools providers describe "github-provider" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --format="value(name)"
```

### 4. Create Service Account

```bash
# Create service account for GitHub Actions
gcloud iam service-accounts create github-actions \
    --display-name="GitHub Actions Service Account" \
    --description="Service account for GitHub Actions CI/CD"

# Get the service account email
export SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
```

### 5. Grant Permissions

```bash
# Grant GCR push/pull permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin"

# Alternative: Artifact Registry permissions (recommended for new projects)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.writer"

# Grant workload identity user permission for GitHub repository
gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/your-org/your-repo"
```

Replace:
- `PROJECT_NUMBER`: Your GCP project number (not ID)
- `your-org/your-repo`: Your GitHub organization and repository name

### 6. Configure GitHub Repository

Add these variables to your GitHub repository:

**Repository Settings → Secrets and variables → Actions → Variables:**

```yaml
GCP_PROJECT_ID: your-gcp-project-id
GCP_REGION: us-central1
```

**Repository Settings → Secrets and variables → Actions → Secrets:**

```yaml
# No secrets needed for Workload Identity! 
# But if your GitOps repo is private, you may need:
GITOPS_REPO_TOKEN: <classic PAT with repo scope>
```

### 7. Update Workflow Configuration

In your caller workflow, update these values:

```yaml
workload_identity_provider: 'projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
service_account: 'github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com'
```

To find your PROJECT_NUMBER:
```bash
gcloud projects describe $PROJECT_ID --format="value(projectNumber)"
```

## Verification

Test the setup with this minimal workflow:

```yaml
name: Test GCP Auth
on: push

permissions:
  contents: read
  id-token: write

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
          service_account: 'github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com'
      
      - name: Verify Auth
        run: gcloud auth list
```

## Troubleshooting

### Error: "Permission denied" on GCR push

Ensure the service account has storage admin role:
```bash
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --format='table(bindings.role)' \
    --filter="bindings.members:github-actions@"
```

### Error: "Failed to fetch access token"

Verify the workload identity provider mapping:
```bash
gcloud iam workload-identity-pools providers describe github-provider \
    --workload-identity-pool=github-pool \
    --location=global \
    --format="value(attributeMapping)"
```

### Error: "Attribute condition not met"

If you added attribute conditions, verify the repository matches:
```bash
# Check current condition
gcloud iam workload-identity-pools providers describe github-provider \
    --workload-identity-pool=github-pool \
    --location=global \
    --format="value(attributeCondition)"
```

## Security Best Practices

1. **Least Privilege**: Grant only necessary permissions to the service account
2. **Repository Restriction**: Use attribute conditions to limit which repos can authenticate
3. **No Long-lived Keys**: Never download service account keys
4. **Audit Logging**: Enable audit logs for IAM service
5. **Rotate Regularly**: Workload identity tokens are short-lived (1 hour by default)

## Multiple Repositories

To allow multiple repositories to use the same pool:

```bash
# For org/repo1
gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/your-org/repo1"

# For org/repo2
gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/your-org/repo2"
```

## References

- [Google Cloud Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [google-github-actions/auth](https://github.com/google-github-actions/auth)
