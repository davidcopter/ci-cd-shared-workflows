#!/usr/bin/env bash
#
# Tag Derivation Script for CI/CD Pipeline
# This script derives Docker image tags based on Git references
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to derive tags based on git reference
derive_tags() {
    local ref_name="${1:-}"
    local full_sha="${2:-}"
    local git_ref="${3:-}"
    
    if [[ -z "$ref_name" || -z "$full_sha" ]]; then
        log_error "Usage: derive_tags <ref_name> <full_sha> [git_ref]"
        exit 1
    fi
    
    # Get short SHA (first 7 characters)
    local short_sha="${full_sha:0:7}"
    
    # Initialize output variables
    local primary_tag=""
    local additional_tags=""
    local is_semantic="false"
    local tag_type=""
    
    log_info "Processing ref: $ref_name (SHA: $short_sha)"
    
    # Case 1: Main/Master branch - Semantic versioning + latest
    if [[ "$ref_name" == "main" || "$ref_name" == "master" ]]; then
        tag_type="main"
        
        # Get the latest semantic version tag
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
        
        log_info "Latest git tag: $latest_tag"
        
        # Parse semantic version (supports v1.2.3 or 1.2.3)
        if [[ "$latest_tag" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            local major="${BASH_REMATCH[1]}"
            local minor="${BASH_REMATCH[2]}"
            local patch="${BASH_REMATCH[3]}"
            
            # Increment patch version for new build
            local new_patch=$((patch + 1))
            primary_tag="${major}.${minor}.${new_patch}"
            is_semantic="true"
            
            log_info "Semantic version detected: ${major}.${minor}.${patch} -> ${primary_tag}"
        else
            # Fallback: use sha-based tag
            primary_tag="main-${short_sha}"
            log_warn "No semantic version tag found, using: $primary_tag"
        fi
        
        # Always tag main/master as latest
        additional_tags="latest"
        
    # Case 2: Release branches - Release Candidates
    elif [[ "$ref_name" =~ ^release/([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        tag_type="release"
        
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        # Calculate RC number based on commit count
        # This ensures each commit on release branch gets unique RC tag
        local rc_number
        rc_number=$(git rev-list --count HEAD 2>/dev/null || echo "1")
        
        primary_tag="${major}.${minor}.${patch}-rc.${rc_number}"
        is_semantic="true"
        
        log_info "Release candidate: $primary_tag"
        
    # Case 3: Develop branch
    elif [[ "$ref_name" == "develop" ]]; then
        tag_type="develop"
        primary_tag="develop-${short_sha}"
        log_info "Develop branch tag: $primary_tag"
        
    # Case 4: Tags (when workflow triggers on tag push)
    elif [[ "$git_ref" == refs/tags/* ]]; then
        tag_type="tag"
        
        # Remove 'v' prefix if present for consistency
        if [[ "$ref_name" =~ ^v(.+)$ ]]; then
            primary_tag="${BASH_REMATCH[1]}"
        else
            primary_tag="$ref_name"
        fi
        
        # Check if it's a semantic version
        if [[ "$primary_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.+)?$ ]]; then
            is_semantic="true"
            
            # Tag as latest if it's a release version (no pre-release)
            if [[ ! "$primary_tag" =~ - ]]; then
                additional_tags="latest"
            fi
        fi
        
        log_info "Git tag detected: $primary_tag"
        
    # Case 5: Feature branches and others
    else
        tag_type="feature"
        
        # Sanitize branch name:
        # 1. Replace slashes with dashes
        # 2. Remove special characters except alphanumeric, dots, underscores, dashes
        # 3. Convert to lowercase
        # 4. Limit to 43 chars to keep total tag under 50 chars (with -sha suffix)
        local sanitized_ref
        sanitized_ref=$(echo "$ref_name" | \
            sed 's/\//-/g' | \
            sed 's/[^a-zA-Z0-9._-]//g' | \
            tr '[:upper:]' '[:lower:]')
        
        if [[ ${#sanitized_ref} -gt 43 ]]; then
            sanitized_ref="${sanitized_ref:0:43}"
            log_warn "Branch name truncated to: $sanitized_ref"
        fi
        
        primary_tag="${sanitized_ref}-${short_sha}"
        log_info "Feature branch tag: $primary_tag"
    fi
    
    # Output results
    echo "primary_tag=$primary_tag"
    echo "additional_tags=$additional_tags"
    echo "is_semantic=$is_semantic"
    echo "tag_type=$tag_type"
    echo "short_sha=$short_sha"
    
    # Export for GitHub Actions
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "image_tag=$primary_tag" >> "$GITHUB_OUTPUT"
        echo "additional_tags=$additional_tags" >> "$GITHUB_OUTPUT"
        echo "is_semantic_version=$is_semantic" >> "$GITHUB_OUTPUT"
        echo "tag_type=$tag_type" >> "$GITHUB_OUTPUT"
        echo "short_sha=$short_sha" >> "$GITHUB_OUTPUT"
    fi
}

# Function to validate semantic version
is_valid_semver() {
    local version="$1"
    
    # Semantic versioning regex (simplified)
    # Matches: 1.2.3 or 1.2.3-alpha.1 or 1.2.3-rc.1+build.123
    if [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Main execution
main() {
    # Check if running in GitHub Actions
    if [[ -n "${GITHUB_REF:-}" && -n "${GITHUB_SHA:-}" ]]; then
        # GitHub Actions environment
        local ref_name="${GITHUB_REF_NAME:-}"
        local full_sha="${GITHUB_SHA:-}"
        local git_ref="${GITHUB_REF:-}"
        
        log_info "Running in GitHub Actions environment"
        derive_tags "$ref_name" "$full_sha" "$git_ref"
    else
        # Local execution - parse arguments
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 <ref_name> <full_sha> [git_ref]"
            echo ""
            echo "Examples:"
            echo "  $0 main abc123def456"
            echo "  $0 release/1.2.0 abc123def456 refs/heads/release/1.2.0"
            echo "  $0 feature/my-feature abc123def456 refs/heads/feature/my-feature"
            exit 1
        fi
        
        derive_tags "$1" "$2" "${3:-}"
    fi
}

# Run main function
main "$@"
