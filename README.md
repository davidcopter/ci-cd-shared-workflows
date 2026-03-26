# CI/CD Shared Workflows

Production-ready, reusable GitHub Actions workflows for container image deployment with dynamic tagging and GitHub Container Registry.

## Features

✅ **Reusable Workflow** - Single template used across multiple services
✅ **Dynamic Tagging** - Semantic versioning, release candidates, and feature branch tags
✅ **GHCR Authentication** - Automatic via `GITHUB_TOKEN` — no cloud credentials needed
✅ **Docker Buildx** - Multi-platform builds with intelligent layer caching
✅ **Helm GitOps** - Automated PRs to update Helm chart values
✅ **Security Hardened** - Non-root containers, minimal permissions, short-lived tokens

## Quick Start

### 1. Set Up GHCR Authentication

No external setup required. GitHub Container Registry authenticates automatically via `GITHUB_TOKEN`.

Simply add `packages: write` to your caller workflow permissions:

```yaml
permissions:
  contents: read
  packages: write
  pull-requests: write
```

See [GHCR setup guide](docs/setup-ghcr.md) for package visibility settings and cross-org access.

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
  packages: write
  pull-requests: write

jobs:
  deploy:
    uses: davidcopter/ci-cd-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
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
│  │  │  (dynamic)   │→ │ to GHCR      │→ │ GitOps Repo  │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
        ┌──────────────────────┐      ┌──────────────────────┐
        │   GitHub             │      │   GitOps Repository  │
        │   ┌────────────────┐ │      │   ┌────────────────┐ │
        │   │ Container      │ │      │   │ Helm Values    │ │
        │   │ Registry(GHCR) │ │      │   │ Updated by PR  │ │
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
│   ├── setup-ghcr.md                   # GHCR authentication setup
│   └── tagging-strategy.md             # Tagging documentation
└── README.md                           # This file
```

## Workflow Inputs

| Input                  | Required | Default                   | Description                          |
| ---------------------- | -------- | ------------------------- | ------------------------------------ |
| `service_name`         | ✅       | -                         | Service name (used for image naming) |
| `dockerfile_path`      | ❌       | `./Dockerfile`            | Path to Dockerfile                   |
| `docker_build_context` | ❌       | `.`                       | Docker build context                 |
| `gitops_repo`          | ✅       | -                         | GitOps repo (owner/repo)             |
| `helm_chart_path`      | ✅       | -                         | Path to values.yaml in GitOps repo   |
| `enable_cache`         | ❌       | `true`                    | Enable Docker layer caching          |
| `platforms`            | ❌       | `linux/amd64,linux/arm64` | Target platforms                     |
| `build_args`           | ❌       | (empty)                   | Additional build arguments (one per line, KEY=VALUE format) |

## Custom Build Arguments

You can pass additional build arguments to the Docker build process using the `build_args` input. These are merged with the default build arguments (`BUILD_DATE`, `VCS_REF`, `VERSION`).

### Usage Example

```yaml
jobs:
  deploy:
    uses: your-org/github-actions-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/my-service/values.yaml
      
      # Custom build arguments using GitHub context and variables
      build_args: |
        CACHE_BUST=${{ github.run_id }}
        BUILD_NUMBER=${{ github.run_number }}
        BUILDER=${{ github.actor }}
        API_ENDPOINT=${{ vars.API_ENDPOINT || 'https://api.default.com' }}
        ENVIRONMENT=${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
        DB_PASSWORD=${{ secrets.DB_PASSWORD }}
```

### Available GitHub Context Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `${{ github.run_id }}` | Unique ID for each workflow run | `1234567890` |
| `${{ github.run_number }}` | Sequential build number | `42` |
| `${{ github.actor }}` | User who triggered the workflow | `octocat` |
| `${{ github.sha }}` | Commit SHA | `abc123...` |
| `${{ github.ref_name }}` | Branch or tag name | `main`, `v1.0.0` |
| `${{ github.ref }}` | Full ref path | `refs/heads/main` |
| `${{ vars.NAME }}` | Repository/org variables | Custom config values |
| `${{ secrets.NAME }}` | Repository/org secrets | Sensitive values |

### Common Use Cases

**1. Cache Busting**
```yaml
build_args: |
  CACHE_BUST=${{ github.run_id }}
```

**2. Environment-Specific Configuration**
```yaml
build_args: |
  ENVIRONMENT=${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
  API_URL=${{ github.ref == 'refs/heads/main' && 'https://api.prod.com' || 'https://api.dev.com' }}
```

**3. Using Repository Variables**
```yaml
build_args: |
  API_ENDPOINT=${{ vars.API_ENDPOINT }}
  FEATURE_FLAG_X=${{ vars.ENABLE_FEATURE_X }}
```

**4. Using Secrets (sensitive values)**
```yaml
build_args: |
  DB_PASSWORD=${{ secrets.DB_PASSWORD }}
  API_KEY=${{ secrets.API_KEY }}
```

**5. Build Metadata**
```yaml
build_args: |
  BUILD_NUMBER=${{ github.run_number }}
  BUILD_ID=${{ github.run_id }}
  BUILDER=${{ github.actor }}
  COMMIT_SHA=${{ github.sha }}
```

### How to Set Up Variables and Secrets

**Repository Variables** (non-sensitive):
1. Go to repository **Settings → Secrets and variables → Variables**
2. Click "New repository variable"
3. Enter Name (e.g., `API_ENDPOINT`) and Value
4. Click "Add variable"

**Repository Secrets** (sensitive):
1. Go to repository **Settings → Secrets and variables → Secrets**
2. Click "New repository secret"
3. Enter Name (e.g., `DB_PASSWORD`) and Value
4. Click "Add secret"

**Using GitHub CLI**:
```bash
# Set a variable
gh variable set API_ENDPOINT --body "https://api.example.com"

# Set a secret
echo "my-secret-value" | gh secret set DB_PASSWORD
```

### How It Works

The workflow automatically includes these default build arguments:
- `BUILD_DATE` - Timestamp of the build
- `VCS_REF` - Git commit SHA
- `VERSION` - Derived image tag

Your custom `build_args` are appended to these defaults, so you can override them if needed or add new ones.

### Dockerfile Example

Your Dockerfile can accept these build args like this:

```dockerfile
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF
# Custom build args
ARG CACHE_BUST
ARG ENVIRONMENT
ARG API_ENDPOINT

ENV VERSION=${VERSION:-unknown}
ENV BUILD_DATE=${BUILD_DATE:-unknown}
ENV VCS_REF=${VCS_REF:-unknown}
ENV ENVIRONMENT=${ENVIRONMENT:-development}
ENV API_ENDPOINT=${API_ENDPOINT:-https://api.default.com}
```

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
image_uri: ghcr.io/owner/service:1.2.4
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
| Image URI | `ghcr.io/owner/my-service:1.2.4` |
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
| Image URI | `ghcr.io/owner/service:1.2.4` |
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

### GHCR Authentication

- ✅ **No static credentials** stored anywhere
- ✅ **Short-lived tokens** that expire when the workflow run completes
- ✅ **Automatic authentication** via `GITHUB_TOKEN`
- ✅ **Fine-grained access** governed by GitHub's permission model

### Docker Security

- ✅ **Non-root user** execution
- ✅ **Multi-stage builds** to minimize attack surface
- ✅ **Minimal base images** (Alpine Linux)
- ✅ **No secrets in layers** ( BuildKit secrets support)
- ✅ **Image scanning** ready (integrate with Trivy/Clair)

### Permissions

```yaml
permissions:
  contents: read        # Only read repository contents
  packages: write       # Required for GHCR push
  pull-requests: write  # Required for creating GitOps PRs
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
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/api-service/values.yaml

  deploy-frontend:
    uses: your-org/github-actions-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: frontend-service
      dockerfile_path: ./services/frontend/Dockerfile
      docker_build_context: ./services/frontend
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

### 2. GHCR Registry Cache

- **Scope:** Shared across all builds
- **Persistence:** Until manually deleted
- **Use case:** Layer reuse across branches/environments

```yaml
cache-from: |
  type=gha,scope=${{ inputs.service_name }}
  type=registry,ref=ghcr.io/owner/service:buildcache
cache-to: |
  type=gha,scope=${{ inputs.service_name }},mode=max
  type=registry,ref=ghcr.io/owner/service:buildcache,mode=max
```

## Monitoring & Observability

### GitHub Actions Summary

Each run generates a detailed summary:

```markdown
## CI/CD Pipeline Summary

**Service:** my-service
**Image Tag:** 1.2.4
**Image URI:** ghcr.io/owner/my-service:1.2.4
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

### "denied: permission_denied: write_package" on GHCR push

Ensure `packages: write` is in your caller workflow's `permissions` block. Reusable workflows inherit permissions from the caller.

### "unauthorized: authentication required"

The `GITHUB_TOKEN` is scoped to the triggering repository. For cross-org pushes, use a PAT with `write:packages` scope stored as a secret.

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
   gitops_repo: ${{ vars.GITOPS_REPO }}
   ```

3. **Enable branch protection** for main branch

4. **Require PR reviews** for GitOps repository changes

5. **Set up notifications** for deployment status:
   - Use the included `notify-deployment` job in your caller workflow for GitHub commit comments
   - Or integrate with Slack, Teams, Discord using the exported outputs
   - See [Notifications](#notifications) section for examples

6. **Monitor GHCR storage** (cache images can grow large; free tier has limits)

## Secrets & Variables Setup

This section lists all GitHub repository variables and secrets needed for the CI/CD workflow to function.

### Repository Variables (Non-Sensitive)

Repository variables are set at **Settings → Secrets and variables → Variables**.

No required variables — GHCR authentication is handled automatically via `GITHUB_TOKEN`.

| Variable         | Required | Description                                              | Where to Get                                                                                                                                                                     |
| ---------------- | -------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SLACK_WEBHOOK`  | ❌       | Slack webhook URL for notifications (optional)           | 1. Go to your Slack workspace<br/>2. Create incoming webhook: https://api.slack.com/messaging/webhooks<br/>3. Configure & copy webhook URL                                       |
| `TEAMS_WEBHOOK`  | ❌       | Microsoft Teams webhook URL for notifications (optional) | 1. Go to Microsoft Teams channel<br/>2. Click `⋯` (More options) → Connectors<br/>3. Search "Incoming Webhook"<br/>4. Configure & copy webhook URL                               |
| `DISCORD_WEBHOOK`| ❌       | Discord webhook URL for notifications (optional)         | 1. Go to Discord server settings → Integrations → Webhooks<br/>2. Create New Webhook<br/>3. Copy webhook URL                                                                    |

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

- [ ] **Workflow Permissions**: Confirm `packages: write` is in your caller workflow's `permissions` block
- [ ] **GitOps Repo**: Verify write access to the GitOps repository
- [ ] **GITOPS_TOKEN** (if needed): Set at `Settings → Secrets and variables → Secrets` if GitOps repo is in a different org
- [ ] **Notifications** (Optional): Test webhook URLs if setting up Slack/Teams/Discord

### Troubleshooting Secrets & Variables

**Error: "denied: permission_denied: write_package"**

- Add `packages: write` to your caller workflow's `permissions` block
- Reusable workflows inherit permissions from the caller — the caller must grant this explicitly

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

### From GCR (Google Container Registry)

1. Remove `gcp_project_id`, `workload_identity_provider`, `service_account` from your caller workflow `with:` block
2. Replace `id-token: write` permission with `packages: write`
3. Update Helm values `image.repository` from `gcr.io/project/service` to `ghcr.io/owner/service`
4. Migrate existing images if needed (optional — new builds will push to GHCR automatically)

### From Docker Hub

1. Remove Docker Hub credentials from GitHub secrets
2. Add `packages: write` to your workflow permissions
3. Update image references in Helm charts to `ghcr.io/owner/service`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with a sample service
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- 📖 [GHCR Setup](docs/setup-ghcr.md)
- 🏷️ [Tagging Strategy](docs/tagging-strategy.md)
- 🐛 [Open an Issue](../../issues)
- 💬 [Discussions](../../discussions)

## References

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Semantic Versioning](https://semver.org/)
- [GitOps with Helm](https://helm.sh/docs/)
