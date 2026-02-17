# Local Development Makefile for CI/CD Workflow Testing

.PHONY: help test-tags test-docker lint validate

# Default target
help:
	@echo "Available targets:"
	@echo "  make test-tags BRANCH=main          - Test tag derivation for a branch"
	@echo "  make test-tags BRANCH=develop       - Test tag derivation for develop"
	@echo "  make test-tags BRANCH=release/1.0.0 - Test tag derivation for release"
	@echo "  make test-docker                    - Test Docker build locally"
	@echo "  make validate                       - Validate workflow files"
	@echo "  make lint                           - Run linting checks"

# Test tag derivation for current branch
test-tags:
	@if [ -z "$(BRANCH)" ]; then \
		echo "Usage: make test-tags BRANCH=<branch-name>"; \
		echo "Examples:"; \
		echo "  make test-tags BRANCH=main"; \
		echo "  make test-tags BRANCH=develop"; \
		echo "  make test-tags BRANCH=feature/my-feature"; \
		echo "  make test-tags BRANCH=release/1.2.0"; \
		exit 1; \
	fi
	@echo "Testing tag derivation for branch: $(BRANCH)"
	@./scripts/derive-tags.sh \
		"$(BRANCH)" \
		"$$(git rev-parse HEAD 2>/dev/null || echo 'abc1234567890abcdef1234567890abcdef123456')" \
		"refs/heads/$(BRANCH)"

# Test Docker build locally
test-docker:
	@echo "Building Docker image locally..."
	@docker buildx build \
		--platform linux/amd64 \
		--tag test-image:local \
		--build-arg VERSION=local-test \
		--build-arg BUILD_DATE=$$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
		--build-arg VCS_REF=$$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown') \
		-f examples/Dockerfile \
		examples/
	@echo "Build complete: test-image:local"

# Test Docker build with cache
test-docker-cache:
	@echo "Building Docker image with cache..."
	@docker buildx build \
		--platform linux/amd64 \
		--tag test-image:cached \
		--cache-from type=local,src=/tmp/.buildx-cache \
		--cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max \
		--build-arg VERSION=local-test \
		-f examples/Dockerfile \
		examples/
	@echo "Build complete: test-image:cached"

# Validate GitHub Actions workflow files
validate:
	@echo "Validating GitHub Actions workflow files..."
	@which actionlint > /dev/null 2>&1 || (echo "Installing actionlint..." && \
		curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.sh | bash && \
		sudo mv actionlint /usr/local/bin/)
	@actionlint .github/workflows/*.yml
	@echo "✓ Workflow files validated successfully"

# Lint shell scripts
lint:
	@echo "Linting shell scripts..."
	@which shellcheck > /dev/null 2>&1 || (echo "Please install shellcheck: https://github.com/koalaman/shellcheck" && exit 1)
	@shellcheck scripts/*.sh
	@echo "✓ Shell scripts linted successfully"

# Clean up local test artifacts
clean:
	@echo "Cleaning up local artifacts..."
	@docker rmi test-image:local test-image:cached 2>/dev/null || true
	@docker builder prune -f 2>/dev/null || true
	@echo "✓ Cleanup complete"

# Show current git info
info:
	@echo "Current Git Info:"
	@echo "  Branch: $$(git branch --show-current 2>/dev/null || echo 'N/A')"
	@echo "  Commit: $$(git rev-parse HEAD 2>/dev/null || echo 'N/A')"
	@echo "  Short SHA: $$(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
	@echo "  Latest Tag: $$(git describe --tags --abbrev=0 2>/dev/null || echo 'N/A')"

# Test all branch types
test-all-tags: info
	@echo "\n=== Testing Main Branch ==="
	@BRANCH=main $(MAKE) test-tags 2>&1 | grep -E "(Processing|primary_tag|additional_tags|is_semantic)"
	@echo "\n=== Testing Develop Branch ==="
	@BRANCH=develop $(MAKE) test-tags 2>&1 | grep -E "(Processing|primary_tag|additional_tags|is_semantic)"
	@echo "\n=== Testing Release Branch ==="
	@BRANCH=release/1.2.0 $(MAKE) test-tags 2>&1 | grep -E "(Processing|primary_tag|additional_tags|is_semantic)"
	@echo "\n=== Testing Feature Branch ==="
	@BRANCH=feature/my-awesome-feature $(MAKE) test-tags 2>&1 | grep -E "(Processing|primary_tag|additional_tags|is_semantic)"
