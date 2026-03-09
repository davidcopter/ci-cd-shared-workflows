# Image Tagging Strategy Documentation

This document explains the dynamic tagging logic implemented in the CI/CD pipeline.

## Overview

The tagging strategy uses **branch-based versioning** to automatically derive appropriate Docker image tags based on the Git reference (branch, tag, or commit). This ensures consistent versioning across environments while maintaining traceability.

## Tagging Rules by Branch Type

### 1. Main/Master Branch

**Rule:** Semantic versioning + `latest` tag

**Logic:**
```bash
# 1. Find the latest semantic version tag in git
latest_tag=$(git describe --tags --abbrev=0)  # e.g., "v1.2.3"

# 2. Parse and increment patch version
# v1.2.3 → 1.2.4

# 3. Tag as: 1.2.4 AND latest
```

**Examples:**
- Latest git tag: `v1.2.3` → Docker tags: `1.2.4`, `latest`
- Latest git tag: `v2.0.0` → Docker tags: `2.0.1`, `latest`
- No git tags → Docker tags: `main-abc1234`

**Use Case:** Production deployments

**Helm Values Update:**
```yaml
image:
  repository: ghcr.io/owner/service
  tag: "1.2.4"
  pullPolicy: IfNotPresent
```

### 2. Release Branches

**Pattern:** `release/X.Y.Z`

**Rule:** Release Candidate (RC) tags

**Logic:**
```bash
# 1. Extract version from branch name
# release/1.2.0 → MAJOR=1, MINOR=2, PATCH=0

# 2. Calculate RC number from commit count
rc_number=$(git rev-list --count HEAD)

# 3. Tag as: 1.2.0-rc.N
```

**Examples:**
- Branch: `release/1.2.0`, 5 commits → Docker tag: `1.2.0-rc.5`
- Branch: `release/2.0.0`, 12 commits → Docker tag: `2.0.0-rc.12`

**Use Case:** Pre-release testing, QA environments

**Helm Values Update:**
```yaml
image:
  tag: "1.2.0-rc.5"
```

### 3. Develop Branch

**Rule:** Branch name + short SHA

**Logic:**
```bash
# Tag as: develop-abc1234
```

**Example:**
- Branch: `develop`, SHA: `abc1234567890` → Docker tag: `develop-abc1234`

**Use Case:** Development environment, continuous integration

### 4. Feature Branches

**Pattern:** Any non-standard branch

**Rule:** Sanitized branch name + short SHA

**Logic:**
```bash
# 1. Sanitize branch name
# feature/user-auth → feature-user-auth
# fix/bug-123 → fix-bug-123
# dependabot/npm_and_yarn/express-4.18.0 → dependabot-npm-and-yarn-exp

# 2. Append short SHA
# Tag as: feature-user-auth-abc1234
```

**Examples:**
- Branch: `feature/new-dashboard` → Docker tag: `feature-new-dashboard-abc1234`
- Branch: `hotfix/critical-bug` → Docker tag: `hotfix-critical-bug-def5678`
- Branch: `dependabot/npm_and_yarn/lodash-4.17.21` → Docker tag: `dependabot-npm-and-yarn-lodash-ghi9012`

**Use Case:** Feature testing, PR previews, ephemeral environments

### 5. Git Tags

**Rule:** Use tag value directly (minus 'v' prefix)

**Logic:**
```bash
# Tag push: v1.2.0 → Docker tag: 1.2.0
# Tag push: 2.0.0-alpha.1 → Docker tag: 2.0.0-alpha.1
```

**Examples:**
- Git tag: `v1.2.0` → Docker tags: `1.2.0`, `latest`
- Git tag: `v2.0.0-rc.1` → Docker tag: `2.0.0-rc.1`

**Use Case:** Manual releases, specific version deployments

## Tag Derivation Logic Flow

```
Git Push Event
       │
       ▼
┌─────────────────┐
│ Get Git Ref     │
│ - Branch name   │
│ - Commit SHA    │
└────────┬────────┘
         │
         ▼
┌────────────────────────────────────┐
│ Branch Type Detection              │
│                                    │
│ main/master? ───────► Semantic     │
│                      Versioning    │
│                                    │
│ release/X.Y.Z? ─────► Release      │
│                      Candidate     │
│                                    │
│ develop? ───────────► develop-SHA  │
│                                    │
│ feature/*? ─────────► Branch-SHA   │
│                                    │
│ tag? ───────────────► Tag value    │
└────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ Sanitize &      │
│ Format Tags     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Output:         │
│ - Primary tag   │
│ - Additional    │
│   tags          │
│ - Semantic      │
│   version flag  │
└─────────────────┘
```

## Shell Script Implementation

### Key Functions

#### `derive_tags()`
Main function that determines tag based on Git reference:

```bash
derive_tags() {
    local ref_name="$1"      # e.g., "main" or "feature/my-feature"
    local full_sha="$2"      # Full commit SHA
    local git_ref="$3"       # Full Git ref e.g., refs/heads/main
    
    # Extract short SHA (7 chars)
    local short_sha="${full_sha:0:7}"
    
    # Branch-based logic using pattern matching
    case "$ref_name" in
        main|master)
            # Semantic version logic
            ;;
        release/*)
            # RC version logic
            ;;
        develop)
            # Develop branch logic
            ;;
        *)
            # Feature branch logic
            ;;
    esac
}
```

#### Branch Name Sanitization

```bash
sanitize_branch_name() {
    local branch="$1"
    
    # Step 1: Replace slashes with dashes
    branch=$(echo "$branch" | sed 's/\//-/g')
    
    # Step 2: Remove special characters
    # Keep only: alphanumeric, dots, underscores, dashes
    branch=$(echo "$branch" | sed 's/[^a-zA-Z0-9._-]//g')
    
    # Step 3: Convert to lowercase
    branch=$(echo "$branch" | tr '[:upper:]' '[:lower:]')
    
    # Step 4: Truncate to 43 chars
    # (leaves room for -sha7 = 50 chars total)
    if [[ ${#branch} -gt 43 ]]; then
        branch="${branch:0:43}"
    fi
    
    echo "$branch"
}
```

#### Semantic Version Parsing

```bash
parse_semver() {
    local tag="$1"
    
    # Regex for semantic versioning
    # Matches: 1.2.3, v1.2.3, 1.2.3-alpha, 1.2.3-rc.1, etc.
    if [[ "$tag" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        echo "Major: $major, Minor: $minor, Patch: $patch"
        return 0
    fi
    
    return 1
}
```

## Tag Format Standards

### Docker Tag Constraints

- Max length: **128 characters** (we limit to 50 for readability)
- Valid characters: `[a-z0-9_.-]`
- Cannot start with `.` or `-`
- Case insensitive (stored as lowercase)

### Our Tag Patterns

| Branch Type | Pattern | Example | Length |
|------------|---------|---------|--------|
| Main | `M.m.p` | `1.2.4` | 5-11 |
| Release | `M.m.p-rc.N` | `1.2.0-rc.5` | 10-15 |
| Develop | `develop-SHA7` | `develop-abc1234` | 15 |
| Feature | `name-SHA7` | `feat-auth-abc1234` | 15-50 |

## Integration with GitOps

### Helm Values Structure

```yaml
# charts/my-service/values.yaml
image:
  repository: ghcr.io/owner/my-service
  tag: ""  # Updated by CI/CD
  pullPolicy: IfNotPresent

# Environment-specific overrides
# environments/dev/values.yaml
image:
  tag: "develop-abc1234"

# environments/prod/values.yaml
image:
  tag: "1.2.4"
```

### GitOps Update Process

1. **Build** image with derived tags
2. **Push** to GHCR
3. **Checkout** GitOps repository
4. **Update** `image.tag` in Helm values
5. **Create** PR with deployment details
6. **Auto-merge** (optional) or manual review
7. **ArgoCD/Flux** detects change and deploys

### GitOps Pull Request Template

```markdown
## Deployment Update

**Service:** my-service
**Image Tag:** `1.2.4`
**Full Image:** `ghcr.io/owner/my-service:1.2.4`

### Changes
- **Source Commit:** abc1234567890abcdef1234567890abcdef123456
- **Source Branch:** main
- **Triggered By:** github-actions

### Rollback
Revert this PR to rollback to previous version.
```

## Benefits of This Strategy

1. **Traceability**: Every image can be traced back to a specific commit
2. **Immutability**: Tags are unique and never reused
3. **Environment Alignment**: Tag type indicates target environment
4. **Semantic Clarity**: Production tags follow SemVer standards
5. **Cache Efficiency**: Similar builds share layer caches
6. **GitOps Friendly**: Automated PRs with clear context

## Testing Tag Derivation

### Local Testing

```bash
# Navigate to your repo
cd /path/to/your-repo

# Test main branch
./scripts/derive-tags.sh main $(git rev-parse HEAD) refs/heads/main

# Test release branch
./scripts/derive-tags.sh release/1.2.0 $(git rev-parse HEAD) refs/heads/release/1.2.0

# Test feature branch
./scripts/derive-tags.sh feature/my-feature $(git rev-parse HEAD) refs/heads/feature/my-feature
```

### Expected Output

```bash
# Main branch with existing tag v1.2.3
[INFO] Processing ref: main (SHA: abc1234)
[INFO] Latest git tag: v1.2.3
[INFO] Semantic version detected: 1.2.3 -> 1.2.4
primary_tag=1.2.4
additional_tags=latest
is_semantic=true
tag_type=main
short_sha=abc1234

# Release branch
[INFO] Processing ref: release/1.2.0 (SHA: def5678)
[INFO] Release candidate: 1.2.0-rc.5
primary_tag=1.2.0-rc.5
additional_tags=
is_semantic=true
tag_type=release
short_sha=def5678

# Feature branch
[INFO] Processing ref: feature/user-auth (SHA: ghi9012)
primary_tag=feature-user-auth-ghi9012
additional_tags=
is_semantic=false
tag_type=feature
short_sha=ghi9012
```

## Edge Cases Handled

1. **No git tags**: Falls back to `main-SHA` format
2. **Invalid semantic versions**: Treated as feature branches
3. **Long branch names**: Truncated to 43 characters
4. **Special characters**: Sanitized or removed
5. **Case sensitivity**: All converted to lowercase
6. **Duplicate tags**: SHA ensures uniqueness

## Migration from Other Strategies

### From Git SHA Only

Old: `abc1234` → New: `1.2.4`, `latest` (main) or `feature-name-abc1234`

### From Build Number

Old: `build-123` → New: `1.2.4` (semantic versioning)

### From Timestamp

Old: `20240115-120000` → New: `develop-abc1234` or semantic version

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Docker Tagging Best Practices](https://docs.docker.com/develop/dev-best-practices/dockerfile_best-practices/#tagging)
- [GitOps Principles](https://www.weave.works/technologies/gitops/)
