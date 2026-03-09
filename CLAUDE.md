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

This repository is a **shared GitHub Actions reusable workflow** for container deployments using GitHub Container Registry (GHCR). Caller repositories reference `.github/workflows/ci-cd-template.yml` via `workflow_call`.

### Pipeline Flow

The single `build-and-deploy` job in `ci-cd-template.yml` runs these steps in sequence:

1. **Derive Image Tags** — inline bash logic (mirrors `scripts/derive-tags.sh`) determines Docker tags from the Git ref
2. **Login to GHCR** — authenticates to `ghcr.io` via `GITHUB_TOKEN` (requires `packages: write` in caller permissions)
3. **Build & Push** — Docker Buildx multi-platform build pushed to GHCR (`ghcr.io/<owner>/<service>`) with dual caching (GitHub Actions cache + GHCR registry cache)
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

### Required Caller Permissions

The caller workflow must declare:
```yaml
permissions:
  contents: read
  packages: write      # Required for GHCR push
  pull-requests: write # Required for GitOps PRs
```

No GitHub variables or secrets required for registry auth — `GITHUB_TOKEN` is used automatically.

Optional secret: `GITOPS_TOKEN` — only needed when the GitOps repo is in a different org or requires explicit token permissions; falls back to `github.token`.

### Helm Values Update Contract

The workflow supports two `values.yaml` structures controlled by `helm_values_alias` (default: `"app"`):

**With alias (default, `helm_values_alias: "app"`):**
```yaml
app:
  image:
    repository: ghcr.io/<owner>/service-name
    tag: ""   # updated by the workflow
```

**Without alias (`helm_values_alias: ""`):**
```yaml
image:
  repository: ghcr.io/<owner>/service-name
  tag: ""   # updated by the workflow
```

If the root key is absent, the section is appended. The workflow uses `yq` when available, falling back to `sed` (sed only updates `tag:`, not `repository:`).

### Caller Workflow Pattern

```yaml
permissions:
  contents: read
  packages: write
  pull-requests: write

jobs:
  deploy:
    uses: org/ci-cd-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gitops_repo: org/gitops-repo
      helm_chart_path: charts/my-service/values.yaml
      helm_values_alias: app   # default; set to "" for root-level image key
```

See `examples/caller-workflow.yml` for the full pattern including the optional `notify-deployment` job that posts commit comments on success/failure.
