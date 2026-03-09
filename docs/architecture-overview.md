# CI/CD Shared Workflow — Architecture Overview

## Purpose

A **reusable GitHub Actions workflow** (`ci-cd-template.yml`) that standardizes container build and GitOps deployment across all services. Teams reference it via `workflow_call` instead of maintaining their own pipelines.

---

## Pipeline Flow

```
Push/Tag → Derive Image Tag → Login GHCR → Build & Push → Update GitOps → Create PR → (ArgoCD/Flux deploys)
```

1. **Derive Image Tags** — determines Docker tag from the Git ref (see tagging strategy below)
2. **Login to GHCR** — authenticates using `GITHUB_TOKEN` (no extra secrets needed)
3. **Build & Push** — Docker Buildx multi-arch build (`linux/amd64`, `linux/arm64`) pushed to `ghcr.io/<owner>/<service>`
4. **Update GitOps Repo** — patches `image.tag` in the Helm `values.yaml` via `yq` (falls back to `sed`)
5. **Create PR** — opens a PR on the GitOps repo; ArgoCD/Flux picks it up automatically

---

## Tagging Strategy

| Source Branch     | Tag Format              | `latest`? |
|-------------------|-------------------------|-----------|
| `main` / `master` | `M.m.p` (auto-increment patch) | Yes |
| `release/X.Y.Z`  | `X.Y.Z-rc.<commit-count>` | No |
| `develop`         | `develop-<sha7>`        | No |
| `feature/*` / other | `<sanitized-branch>-<sha7>` | No |
| Git tag `v*`      | tag value (no `v`)      | Yes (if non-pre-release) |

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | Yes | — | Docker image name |
| `gitops_repo` | Yes | — | `org/repo` of the GitOps repository |
| `helm_chart_path` | Yes | — | Path to `values.yaml` in GitOps repo |
| `dockerfile_path` | No | `./Dockerfile` | |
| `docker_build_context` | No | `.` | |
| `platforms` | No | `linux/amd64,linux/arm64` | Multi-arch targets |
| `enable_cache` | No | `true` | GHA + registry layer cache |

---

## Outputs

`image_tag`, `image_uri`, `is_semantic_version`, `deployment_status`, `build_duration_seconds`, `gitops_pr_number`, `gitops_pr_url`

---

## Required Caller Permissions

```yaml
permissions:
  contents: read
  packages: write      # GHCR push
  pull-requests: write # GitOps PR creation
```

**Secrets:** `GITOPS_TOKEN` (optional) — only needed when GitOps repo is in a different org or requires a different token. Falls back to `github.token`.

---

## GitOps Contract

The workflow expects this structure in the GitOps `values.yaml`:

```yaml
image:
  repository: ghcr.io/<owner>/service-name
  tag: ""   # updated by the workflow
```

If the `image:` key is absent, it is appended automatically.

---

## Caller Example (minimal)

```yaml
jobs:
  deploy:
    uses: org/ci-cd-shared-workflows/.github/workflows/ci-cd-template.yml@main
    with:
      service_name: my-service
      gitops_repo: org/gitops-repo
      helm_chart_path: charts/my-service/values.yaml
    permissions:
      contents: read
      packages: write
      pull-requests: write
```

---

## Key Design Decisions

- **No duplicate pipeline maintenance** — one shared workflow; callers just pass inputs
- **Registry auth is zero-config** — uses built-in `GITHUB_TOKEN`; no manual secret rotation
- **GitOps over direct deploy** — workflow never deploys directly; it creates a PR for human review before ArgoCD/Flux applies changes
- **Dual-layer caching** — GitHub Actions cache + GHCR registry cache for faster builds
- **Semantic versioning only on stable branches** — feature/develop branches get SHA-based tags to avoid polluting version history
