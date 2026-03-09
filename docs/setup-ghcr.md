# GitHub Container Registry (GHCR) Setup Guide

This guide explains how authentication works for GitHub Container Registry and covers any additional configuration you may need.

## How Authentication Works

GHCR authentication is **automatic** — no external credentials or cloud setup required.

The reusable workflow authenticates to `ghcr.io` using the built-in `GITHUB_TOKEN`, which GitHub provides automatically for every workflow run. The only requirement is granting the `packages: write` permission in your caller workflow.

```yaml
permissions:
  contents: read
  packages: write    # Required for GHCR push
  pull-requests: write
```

That's it. No GCP projects, service accounts, or identity pools needed.

## Image Naming

Images are pushed to:

```
ghcr.io/<OWNER>/<service_name>:<tag>
```

Where `<OWNER>` is derived automatically from `github.repository_owner` — your GitHub username or organization name.

**Examples:**
- `ghcr.io/my-org/api-service:1.2.4`
- `ghcr.io/my-org/api-service:latest`
- `ghcr.io/my-org/api-service:develop-abc1234`

## Package Visibility

By default, newly published packages are **private**. To make them public:

1. Go to your repository on GitHub
2. Click **Packages** (in the right sidebar or under your profile)
3. Click the package name
4. Click **Package Settings**
5. Under "Danger Zone", click **Change visibility** → Public

Or via GitHub CLI:
```bash
gh api --method PATCH /user/packages/container/SERVICE_NAME \
  --field visibility=public
```

## Cross-Repository Access (GitOps Token)

If your GitOps repository is in a **different organization** or requires explicit permissions, set a `GITOPS_TOKEN` secret in your caller repository:

1. Go to [Personal Access Tokens (Fine-grained)](https://github.com/settings/tokens?type=beta)
2. Create a token with access to your GitOps repository:
   - **Repository access**: Select your GitOps repo
   - **Permissions**: `Contents: Read and write`, `Pull requests: Read and write`, `Metadata: Read`
3. Add it as a repository secret:

```bash
echo "github_pat_..." | gh secret set GITOPS_TOKEN -R your-org/your-repo
```

If the GitOps repo is in the **same organization**, `github.token` is used automatically and no extra setup is needed.

## Caller Workflow Setup

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
    uses: your-org/ci-cd-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gitops_repo: your-org/gitops-repository
      helm_chart_path: charts/my-service/values.yaml
    secrets:
      # Only needed if GitOps repo requires a different token
      GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
```

## Helm Values

Update your GitOps repo's `values.yaml` to reference GHCR:

```yaml
image:
  repository: ghcr.io/your-org/my-service
  tag: ""  # Updated automatically by the workflow
  pullPolicy: IfNotPresent
```

## Troubleshooting

### "denied: permission_denied: write_package"

- Ensure `packages: write` is in your workflow `permissions` block
- Reusable workflows inherit permissions from the caller — the caller must grant `packages: write`

### "unauthorized: authentication required"

- The `GITHUB_TOKEN` is scoped to the repository that triggered the workflow
- If pushing to a package owned by a different org, you need a PAT with `write:packages` scope stored as a secret

### Package not visible after push

- New packages are private by default — see [Package Visibility](#package-visibility) above
- Check **Settings → Actions → General → Workflow permissions** is set to "Read and write permissions" (or use explicit `permissions:` block)

### Kubernetes can't pull the image

For private packages, Kubernetes needs a pull secret:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_PAT_WITH_READ_PACKAGES \
  --namespace=your-namespace
```

Reference it in your Helm values:
```yaml
imagePullSecrets:
  - name: ghcr-pull-secret
```

## Security Notes

- `GITHUB_TOKEN` is **short-lived** — it expires when the workflow run completes
- Tokens are scoped to the triggering repository and organization
- No static credentials are stored anywhere
- Package access is governed by GitHub's standard permission model
