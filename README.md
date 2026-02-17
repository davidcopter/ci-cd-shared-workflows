# CI/CD Shared Workflows

Production-ready, reusable GitHub Actions workflows for container image deployment with dynamic tagging and Workload Identity Federation.

## Features

✅ **Reusable Workflow** - Single template used across multiple services  
✅ **Dynamic Tagging** - Semantic versioning, release candidates, and feature branch tags  
✅ **Workload Identity Federation** - OIDC-based GCP authentication (no static keys)  
✅ **Docker Buildx** - Multi-platform builds with intelligent layer caching  
✅ **Helm GitOps** - Automated PRs to update Helm chart values  
✅ **Security Hardened** - Non-root containers, minimal permissions, audit logging

## Quick Start

### 1. Set Up Workload Identity Federation

Follow the [setup guide](docs/setup-workload-identity.md) to configure GCP authentication.

**Quick Commands:**

```bash
# Set variables
export PROJECT_ID="your-project-id"
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Create pool and provider
gcloud iam workload-identity-pools create "github-pool" --project="${PROJECT_ID}" --location="global"

gcloud iam workload-identity-pools providers create-oidc "github-provider" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --issuer-uri="https://token.actions.githubusercontent.com"

# Create service account
gcloud iam service-accounts create github-actions --display-name="GitHub Actions"

# Grant permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

# Allow GitHub to impersonate SA
gcloud iam service-accounts add-iam-policy-binding \
    github-actions@${PROJECT_ID}.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_ORG/YOUR_REPO"
```

### 2. Use the Reusable Workflow

Create a caller workflow in your service repository:

```yaml
# .github/workflows/deploy.yml
name: Deploy Service

on:
  push:
    branches: [main, develop, "release/**", "feature/**"]

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    uses: your-org/github-actions-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
      workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
      service_account: github-actions@YOUR_PROJECT_ID.iam.gserviceaccount.com
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/my-service/values.yaml
```

### 3. Verify Your GitOps Repo Structure

Ensure your GitOps repo has this structure:

```
gitops-repository/
├── charts/
│   └── my-service/
│       ├── Chart.yaml
│       ├── values.yaml          # ← Updated by workflow
│       └── templates/
└── environments/
    ├── dev/
    │   └── values.yaml
    └── prod/
        └── values.yaml
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GitHub Repository                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        Caller Workflow                               │   │
│  │  Trigger: Push to main/develop/release/**/feature/**                │   │
│  └───────────────────────────────────┬─────────────────────────────────┘   │
│                                      │                                       │
│                                      │ uses                                  │
│                                      ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Reusable Workflow                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │  Derive Tags │  │ Build & Push │  │ Update       │              │   │
│  │  │  (dynamic)   │→ │ to GCR       │→ │ GitOps Repo  │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
        ┌──────────────────────┐      ┌──────────────────────┐
        │   Google Cloud       │      │   GitOps Repository  │
        │   ┌────────────────┐ │      │   ┌────────────────┐ │
        │   │ Container      │ │      │   │ Helm Values    │ │
        │   │ Registry (GCR) │ │      │   │ Updated by PR  │ │
        │   └────────────────┘ │      │   └────────────────┘ │
        └──────────────────────┘      └──────────────────────┘
                                                   │
                                                   │ ArgoCD/Flux watches
                                                   ▼
                                        ┌──────────────────────┐
                                        │   Kubernetes         │
                                        │   Deployment         │
                                        └──────────────────────┘
```

## Tagging Strategy

The workflow automatically derives Docker image tags based on Git references:

| Git Reference   | Tag Format                  | Example                | Environment       |
| --------------- | --------------------------- | ---------------------- | ----------------- |
| `main`/`master` | Semantic version + `latest` | `1.2.4`, `latest`      | Production        |
| `release/X.Y.Z` | Release Candidate           | `1.2.0-rc.5`           | Staging/QA        |
| `develop`       | Branch + SHA                | `develop-abc1234`      | Development       |
| `feature/*`     | Sanitized branch + SHA      | `feature-auth-abc1234` | Feature testing   |
| Git tags        | Tag value                   | `1.2.0`                | Specific versions |

**Read more:** [Tagging Strategy Documentation](docs/tagging-strategy.md)

## File Structure

```
ci-cd-shared-workflows/
├── .github/
│   └── workflows/
│       └── ci-cd-template.yml          # Main reusable workflow
├── examples/
│   ├── caller-workflow.yml             # Example usage
│   └── Dockerfile                      # Multi-stage Dockerfile
├── scripts/
│   └── derive-tags.sh                  # Tag derivation logic
├── docs/
│   ├── setup-workload-identity.md      # GCP OIDC setup
│   └── tagging-strategy.md             # Tagging documentation
└── README.md                           # This file
```

## Workflow Inputs

| Input                        | Required | Default                   | Description                          |
| ---------------------------- | -------- | ------------------------- | ------------------------------------ |
| `service_name`               | ✅       | -                         | Service name (used for image naming) |
| `dockerfile_path`            | ❌       | `./Dockerfile`            | Path to Dockerfile                   |
| `docker_build_context`       | ❌       | `.`                       | Docker build context                 |
| `gcp_project_id`             | ✅       | -                         | GCP project ID                       |
| `gcp_region`                 | ❌       | `us-central1`             | GCP region                           |
| `gcr_hostname`               | ❌       | `gcr.io`                  | GCR hostname                         |
| `workload_identity_provider` | ✅       | -                         | Workload Identity Provider resource  |
| `service_account`            | ✅       | -                         | GCP service account email            |
| `gitops_repo`                | ✅       | -                         | GitOps repo (owner/repo)             |
| `helm_chart_path`            | ✅       | -                         | Path to values.yaml in GitOps repo   |
| `enable_cache`               | ❌       | `true`                    | Enable Docker layer caching          |
| `platforms`                  | ❌       | `linux/amd64,linux/arm64` | Target platforms                     |

## Workflow Outputs

| Output                   | Description                                         |
| ------------------------ | --------------------------------------------------- |
| `image_tag`              | Generated primary image tag                         |
| `image_uri`              | Full image URI with registry                        |
| `is_semantic_version`    | Whether tag follows SemVer                          |
| `deployment_status`      | Deployment status (`success`, `failure`, `skipped`) |
| `build_duration_seconds` | Build duration in seconds                           |
| `gitops_pr_number`       | Pull request number created in GitOps repo          |
| `gitops_pr_url`          | Pull request URL created in GitOps repo             |

## Notifications

The workflow provides comprehensive deployment notifications through GitHub-native channels (no external service required).

### Available Data for Notifications

All deployment data is exported as workflow outputs and job summaries:

```yaml
# From template job
image_tag: 1.2.4
image_uri: gcr.io/project/service:1.2.4
is_semantic_version: true
deployment_status: success
build_duration_seconds: 245
gitops_pr_number: 42
gitops_pr_url: https://github.com/org/gitops-repo/pull/42
```

### GitHub Step Summaries (Automatic)

Each workflow run automatically generates a detailed summary visible in the workflow UI:

```markdown
✅ CI/CD Pipeline Summary

### Deployment Details

| Field     | Value                             |
| --------- | --------------------------------- |
| Service   | my-service                        |
| Image Tag | `1.2.4`                           |
| Image URI | `gcr.io/project/my-service:1.2.4` |
| Branch    | main                              |
| Commit    | abc1234                           |
| Actor     | user                              |

### Build Metadata

| Field            | Value                |
| ---------------- | -------------------- |
| Status           | success              |
| Duration         | 4m 5s                |
| Semantic Version | true                 |
| Start Time       | 2026-02-17T14:30:00Z |

### GitOps Deployment

- PR Created: [#42](https://github.com/org/gitops-repo/pull/42)
```

### Commit Comments (with notify-deployment job)

Use the provided notification job to post detailed comments on commits:

```yaml
notify-deployment:
  needs: call-reusable-workflow
  runs-on: ubuntu-latest
  if: always()

  # Includes Success, Failure, and Cancellation comments
```

**Success Comment Example:**

```markdown
✅ Deployment Successful

Service: my-awesome-service
Triggered by: @developer-name

### Build Details

| Field     | Value                          |
| --------- | ------------------------------ |
| Image Tag | `1.2.4`                        |
| Image URI | `gcr.io/project/service:1.2.4` |
| Branch    | main                           |
| Commit    | abc1234                        |
| Duration  | 4m 5s                          |
| Workflow  | [View Run](...)                |

### GitOps Deployment

A pull request has been created in the GitOps repository to deploy this image:

- [View GitOps PR](https://github.com/org/gitops-repo/pull/42)

### Next Steps

1. Review and merge the GitOps deployment PR
2. Monitor the deployment in your target environment
3. Verify application health and metrics
```

**Failure Comment Example:**

```markdown
❌ Deployment Failed

Service: my-awesome-service
Triggered by: @developer-name
Duration: 2m 15s

### Troubleshooting

1. [View Workflow Details](...)
2. Check the workflow logs for error details
3. Review recent commits for potential issues
4. Check GCP and Docker registry connections
5. Verify your credentials and permissions

### Common Issues

- Docker authentication failed - verify GCP credentials
- Build failed - check Dockerfile syntax and dependencies
- Image push failed - verify GCR access and permissions
- GitOps PR creation failed - check GitOps repository configuration
```

### Extending with External Notifications

The exported outputs make it easy to integrate with external services:

#### Slack Notification Example

```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "${{ needs.call-reusable-workflow.outputs.deployment_status == 'success' && '✅' || '❌' }} Deployment of ${{ inputs.service_name }}",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "Service: *${{ inputs.service_name }}*\nImage: `${{ needs.call-reusable-workflow.outputs.image_tag }}`\nDuration: ${{ needs.call-reusable-workflow.outputs.build_duration_seconds }}s"
            }
          }
        ]
      }
```

#### Teams Notification Example

```yaml
- name: Notify Teams
  if: always()
  uses: jdcargile/ms-teams-notification@v1.3
  with:
    github-token: ${{ github.token }}
    ms-teams-webhook-uri: ${{ secrets.TEAMS_WEBHOOK }}
    notification-color: ${{ needs.call-reusable-workflow.result == 'success' && '32CD32' || 'FF0000' }}
```

#### Discord Notification Example

```yaml
- name: Notify Discord
  if: always()
  uses: SaintBeef/bee-embeds-discord@v1
  with:
    webhook_url: ${{ secrets.DISCORD_WEBHOOK }}
    embed_title: "Deployment ${{ needs.call-reusable-workflow.result == 'success' && '✅ Succeeded' || '❌ Failed' }}"
    embed_description: |
      Service: ${{ inputs.service_name }}
      Image: ${{ needs.call-reusable-workflow.outputs.image_uri }}
      Duration: ${{ needs.call-reusable-workflow.outputs.build_duration_seconds }}s
```

### Notification Triggers

Control when notifications are sent using GitHub Actions conditions:

```yaml
# Success only
if: needs.call-reusable-workflow.result == 'success'

# Failure only
if: needs.call-reusable-workflow.result == 'failure'

# Always (success or failure)
if: always()

# Skip cancelled deployments
if: needs.call-reusable-workflow.result != 'cancelled'
```

### Workload Identity Federation

- ✅ **No static service account keys** stored in GitHub
- ✅ **Short-lived tokens** (1 hour default)
- ✅ **OIDC-based authentication** via GitHub's identity provider
- ✅ **Fine-grained repository access** through attribute conditions

### Docker Security

- ✅ **Non-root user** execution
- ✅ **Multi-stage builds** to minimize attack surface
- ✅ **Minimal base images** (Alpine Linux)
- ✅ **No secrets in layers** ( BuildKit secrets support)
- ✅ **Image scanning** ready (integrate with Trivy/Clair)

### Permissions

```yaml
permissions:
  contents: read # Only read repository contents
  id-token: write # Required for OIDC token exchange
  pull-requests: write # Required for creating GitOps PRs
```

## Example: Multiple Services

Deploy multiple services from one repository:

```yaml
name: Deploy All Services

on:
  push:
    branches: [main, develop]

jobs:
  deploy-api:
    uses: your-org/github-actions-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: api-service
      dockerfile_path: ./services/api/Dockerfile
      docker_build_context: ./services/api
      gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
      workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
      service_account: ${{ vars.SERVICE_ACCOUNT }}
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/api-service/values.yaml

  deploy-frontend:
    uses: your-org/github-actions-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: frontend-service
      dockerfile_path: ./services/frontend/Dockerfile
      docker_build_context: ./services/frontend
      gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
      workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
      service_account: ${{ vars.SERVICE_ACCOUNT }}
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/frontend-service/values.yaml
      platforms: linux/amd64 # Frontend may not need ARM
```

## Caching Strategy

The workflow implements a **dual caching strategy**:

### 1. GitHub Actions Cache (gha)

- **Scope:** Per-service isolation
- **Persistence:** 7 days (GitHub default)
- **Use case:** Speed up repeated builds in same PR

### 2. GCR Registry Cache

- **Scope:** Shared across all builds
- **Persistence:** Until manually deleted
- **Use case:** Layer reuse across branches/environments

```yaml
cache-from: |
  type=gha,scope=${{ inputs.service_name }}
  type=registry,ref=gcr.io/project/service:buildcache
cache-to: |
  type=gha,scope=${{ inputs.service_name }},mode=max
  type=registry,ref=gcr.io/project/service:buildcache,mode=max
```

## Monitoring & Observability

### GitHub Actions Summary

Each run generates a detailed summary:

```markdown
## CI/CD Pipeline Summary

**Service:** my-service
**Image Tag:** 1.2.4
**Image URI:** gcr.io/project/my-service:1.2.4
**Semantic Version:** true
**Branch:** main

### Tags Applied

- Primary: 1.2.4
- Additional: latest

### Pipeline Status: success
```

### GitOps Pull Request

Automated PRs include:

- Image tag and full URI
- Source commit and branch
- Triggered by user
- Rollback instructions
- Deployment checklist

## Troubleshooting

### "Permission denied" on GCR push

```bash
# Verify service account has storage.admin role
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:github-actions@"
```

### "Failed to fetch access token"

1. Verify Workload Identity Provider exists
2. Check attribute mapping is correct
3. Ensure repository matches allowed repositories

### Tags not derived correctly

Run the script locally to debug:

```bash
cd your-repo
./scripts/derive-tags.sh main $(git rev-parse HEAD) refs/heads/main
```

### Docker build cache not working

Ensure BuildKit is enabled:

```yaml
env:
  DOCKER_BUILDKIT: 1
```

## Best Practices

1. **Use version pinning** for reusable workflows:

   ```yaml
   uses: org/workflows/.github/workflows/ci-cd-template.yml@v1.0.0
   ```

2. **Store sensitive values in repository secrets/vars**:

   ```yaml
   gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
   ```

3. **Enable branch protection** for main branch

4. **Require PR reviews** for GitOps repository changes

5. **Set up notifications** for deployment status:
   - Use the included `notify-deployment` job in your caller workflow for GitHub commit comments
   - Or integrate with Slack, Teams, Discord using the exported outputs
   - See [Notifications](#notifications) section for examples

6. **Monitor GCR storage costs** (cache images can grow large)

## Secrets & Variables Setup

This section lists all GitHub repository variables and secrets needed for the CI/CD workflow to function.

### Repository Variables (Non-Sensitive)

Repository variables are set at **Settings → Secrets and variables → Variables**.

| Variable                     | Required | Description                                              | Where to Get                                                                                                                                                                                                                                                                                           |
| ---------------------------- | -------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GCP_PROJECT_ID`             | ✅       | Your Google Cloud project ID                             | 1. Go to [Google Cloud Console](https://console.cloud.google.com)<br/>2. Click project dropdown at top<br/>3. Copy your **Project ID** (not Project Number)                                                                                                                                            |
| `WORKLOAD_IDENTITY_PROVIDER` | ✅       | Full resource path to Workload Identity Provider         | 1. Run: `gcloud iam workload-identity-pools describe github-pool --project=$PROJECT_ID --location=global --format="value(name)"`<br/>2. Then append `/providers/github-provider`<br/>3. Format: `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `SERVICE_ACCOUNT`            | ✅       | GCP service account email for GitHub Actions             | 1. Go to [GCP Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)<br/>2. Find `github-actions` service account<br/>3. Copy email (format: `github-actions@PROJECT_ID.iam.gserviceaccount.com`)                                                                               |
| `SLACK_WEBHOOK`              | ❌       | Slack webhook URL for notifications (optional)           | 1. Go to your Slack workspace<br/>2. Create incoming webhook: https://api.slack.com/messaging/webhooks<br/>3. Configure & copy webhook URL                                                                                                                                                             |
| `TEAMS_WEBHOOK`              | ❌       | Microsoft Teams webhook URL for notifications (optional) | 1. Go to Microsoft Teams channel<br/>2. Click `⋯` (More options) → Connectors<br/>3. Search "Incoming Webhook"<br/>4. Configure & copy webhook URL                                                                                                                                                     |
| `DISCORD_WEBHOOK`            | ❌       | Discord webhook URL for notifications (optional)         | 1. Go to Discord server settings → Integrations → Webhooks<br/>2. Create New Webhook<br/>3. Copy webhook URL                                                                                                                                                                                           |

**How to set variables:**

```bash
# Using GitHub CLI
gh variable set GCP_PROJECT_ID --body "your-project-id" -R org/your-repo
gh variable set WORKLOAD_IDENTITY_PROVIDER --body "projects/123456/..." -R org/your-repo
gh variable set SERVICE_ACCOUNT --body "github-actions@your-project.iam.gserviceaccount.com" -R org/your-repo
```

Or via GitHub UI:

1. Go to repository **Settings → Secrets and variables → Variables**
2. Click "New repository variable"
3. Enter Name and Value
4. Click "Add variable"

### Repository Secrets (Sensitive)

Repository secrets are set at **Settings → Secrets and variables → Secrets**.

| Secret            | Required | Description                                          | Where to Get                                                                                                                                                                                                   | Setup Instructions                                                                                                                                                           |
| ----------------- | -------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GITOPS_TOKEN`    | ❌       | GitHub token for GitOps repository access (optional) | 1. Go to [Personal Access Tokens](https://github.com/settings/tokens)<br/>2. Create a new token (Fine-grained) with permissions:<br/> - `contents: read`<br/> - `pull_requests: write`<br/> - `metadata: read` | Only needed if:<br/>- GitOps repo is in a different organization<br/>- GitOps repo requires specific token permissions<br/>- Otherwise, `github.token` is used automatically |
| `SLACK_WEBHOOK`   | ❌       | Slack webhook URL (store as secret for safety)       | See Slack variable above                                                                                                                                                                                       | Only needed if using Slack notifications                                                                                                                                     |
| `TEAMS_WEBHOOK`   | ❌       | Teams webhook URL (store as secret for safety)       | See Teams variable above                                                                                                                                                                                       | Only needed if using Teams notifications                                                                                                                                     |
| `DISCORD_WEBHOOK` | ❌       | Discord webhook URL (store as secret for safety)     | See Discord variable above                                                                                                                                                                                     | Only needed if using Discord notifications                                                                                                                                   |

**How to set secrets:**

```bash
# Using GitHub CLI
echo "your-token-value" | gh secret set GITOPS_TOKEN -R org/your-repo
echo "https://hooks.slack.com/..." | gh secret set SLACK_WEBHOOK -R org/your-repo
```

Or via GitHub UI:

1. Go to repository **Settings → Secrets and variables → Secrets**
2. Click "New repository secret"
3. Enter Name and Value
4. Click "Add secret"

### Verification Checklist

Verify your setup before running workflows:

- [ ] **GCP Project**: Confirm project ID in [Google Cloud Console](https://console.cloud.google.com)
- [ ] **Service Account**: Verify at [GCP Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts) with roles:
  - `roles/iam.serviceAccountUser` - To use the service account
  - `roles/storage.admin` - To push to GCR
  - `roles/container.developer` - To access Container Registry
- [ ] **Workload Identity**: Confirm pool/provider exists:
  ```bash
  gcloud iam workload-identity-pools list \
    --project=$GCP_PROJECT_ID \
    --location=global \
    --format="table(name,state)"
  ```
- [ ] **Service Account Binding**: Verify GitHub can impersonate it:
  ```bash
  gcloud iam service-accounts get-iam-policy \
    github-actions@$GCP_PROJECT_ID.iam.gserviceaccount.com \
    --format="table(bindings[].members[])"
  ```
- [ ] **GitHub Variables**: Check all 3 required variables are set at `Settings → Secrets and variables → Variables`
- [ ] **GCR Bucket**: Ensure GCR repository is accessible:
  ```bash
  gcloud container images list --project=$GCP_PROJECT_ID
  ```
- [ ] **GitOps Repo**: Verify write access to the GitOps repository
- [ ] **Notifications** (Optional): Test webhook URLs if setting up Slack/Teams/Discord

### Troubleshooting Secrets & Variables

**Error: "Unable to resolve variable"**

- Variable name is case-sensitive
- Ensure variable is in the correct repository (not organization-level)
- Verify at **Settings → Secrets and variables → Variables**

**Error: "Failed to fetch access token"**

- `WORKLOAD_IDENTITY_PROVIDER` is incorrect or expired
- Service account not properly bound to GitHub identity pool
- Repository name doesn't match the binding condition

**Error: "Permission denied" on GCR push**

- Service account missing `roles/storage.admin` role
- Verify: `gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:github-actions@"`

**Error: "403 Forbidden" on GitOps repo**

- `GITOPS_TOKEN` doesn't have `pull_requests: write` permission
- Token is expired or revoked
- Token belongs to user without repo access

**Webhook not receiving notifications**

- Test webhook URL manually:
  ```bash
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test message"}' \
    YOUR_WEBHOOK_URL
  ```
- Check webhook URL is correct and not expired
- Verify channel/server settings allow incoming webhooks

## Migration Guide

### From Static Service Account Keys

1. Remove `GCP_SA_KEY` secret from GitHub
2. Follow [Workload Identity setup](docs/setup-workload-identity.md)
3. Update workflow to use OIDC authentication
4. Delete old service account keys from GCP

### From Docker Hub

1. Update `gcr_hostname` to `gcr.io`
2. Ensure GCR repository exists in GCP
3. Update image references in Helm charts
4. Migrate existing images if needed

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with a sample service
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- 📖 [Workload Identity Setup](docs/setup-workload-identity.md)
- 🏷️ [Tagging Strategy](docs/tagging-strategy.md)
- 🐛 [Open an Issue](../../issues)
- 💬 [Discussions](../../discussions)

## References

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Google Cloud Workload Identity](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Semantic Versioning](https://semver.org/)
- [GitOps with Helm](https://helm.sh/docs/)
