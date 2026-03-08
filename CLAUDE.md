# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Test tag derivation logic for a branch
make test-tags BRANCH=main
make test-tags BRANCH=develop
make test-tags BRANCH=release/1.2.0
make test-tags BRANCH=feature/my-feature

# Test all branch types at once
make test-all-tags

# Build Docker image locally using examples/Dockerfile
make test-docker

# Validate GitHub Actions workflow YAML (requires actionlint)
make validate

# Lint shell scripts (requires shellcheck)
make lint

# Run derive-tags.sh directly
./scripts/derive-tags.sh <ref_name> <full_sha> [git_ref]
# Example: ./scripts/derive-tags.sh main $(git rev-parse HEAD) refs/heads/main
```

## Architecture

This repository is a **shared GitHub Actions reusable workflow** for container deployments to GCP. Caller repositories reference `.github/workflows/ci-cd-template.yml` via `workflow_call`.

### Pipeline Flow

The single `build-and-deploy` job in `ci-cd-template.yml` runs these steps in sequence:

1. **Derive Image Tags** — inline bash logic (mirrors `scripts/derive-tags.sh`) determines Docker tags from the Git ref
2. **Auth to GCP** — OIDC via Workload Identity Federation (`google-github-actions/auth@v2`), no static keys
3. **Build & Push** — Docker Buildx multi-platform build pushed to GCR with dual caching (GitHub Actions cache + GCR registry cache)
4. **Update GitOps Repo** — checks out the caller's GitOps repo, updates `image.tag` in the Helm `values.yaml` using `yq` (or `sed` as fallback)
5. **Create PR** — `peter-evans/create-pull-request@v5` opens a PR on the GitOps repo; ArgoCD/Flux then picks up the change

### Tagging Logic (`scripts/derive-tags.sh`)

The script is the source of truth for tag derivation (the workflow inlines equivalent logic):

| Branch | Tag Format | Notes |
|--------|-----------|-------|
| `main`/`master` | `M.m.p` + `latest` | Auto-increments patch from latest git tag; falls back to `main-SHA` |
| `release/X.Y.Z` | `X.Y.Z-rc.N` | N = total commit count on branch |
| `develop` | `develop-SHA7` | |
| feature/other | `sanitized-branch-SHA7` | Branch truncated to 43 chars; total tag ≤ 50 chars |
| git tags | tag value (strips `v` prefix) | Adds `latest` for non-pre-release tags |

### Required GitHub Variables (in caller repos)

- `GCP_PROJECT_ID` — GCP project ID
- `WORKLOAD_IDENTITY_PROVIDER` — full resource path to the WIF provider
- `SERVICE_ACCOUNT` — `github-actions@PROJECT_ID.iam.gserviceaccount.com`

Optional secret: `GITOPS_TOKEN` — only needed when the GitOps repo is in a different org or requires explicit token permissions; falls back to `github.token`.

### Helm Values Update Contract

The workflow expects this structure in the GitOps repo's `values.yaml`:

```yaml
image:
  repository: gcr.io/project-id/service-name
  tag: ""   # updated by the workflow
```

If the `image:` key is absent, it is appended. The workflow uses `yq` when available, falling back to `sed`.

### Caller Workflow Pattern

```yaml
jobs:
  deploy:
    uses: org/ci-cd-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
      workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
      service_account: ${{ vars.SERVICE_ACCOUNT }}
      gitops_repo: org/gitops-repo
      helm_chart_path: charts/my-service/values.yaml
```

See `examples/caller-workflow.yml` for the full pattern including the optional `notify-deployment` job that posts commit comments on success/failure.
