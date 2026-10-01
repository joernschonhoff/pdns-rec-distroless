CI_REGISTRY_IMAGE ?= registry.gitlab.com/joern_schonhoff/pdns-rec-distroless

# Read PowerDNS Recursor version from VERSION file
PDNS_RECURSOR_VERSION := $(shell cat VERSION)
# Validate version format (semantic versioning: X.Y.Z)
VALIDATE_VERSION := $(shell echo "$(PDNS_RECURSOR_VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' && echo "valid" || echo "invalid")

ifeq ($(VALIDATE_VERSION),invalid)
$(error Invalid VERSION format: "$(PDNS_RECURSOR_VERSION)". Expected semantic versioning (X.Y.Z))
endif

.PHONY: build-prod build-debug build test verify clean clean-images version help

help: ## Show this help message
	@echo "PowerDNS Recursor Distroless - Build Targets"
	@echo "=============================================="
	@echo "Current PowerDNS Recursor version: $(PDNS_RECURSOR_VERSION)"
	@echo ""
	@grep -E '^[a-zA-Z]\S+:.*' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

version: ## Display current PowerDNS Recursor version
	@echo $(PDNS_RECURSOR_VERSION)

build-prod: ## Build production distroless image
	docker buildx build \
		--platform linux/arm64 \
		--build-arg PDNS_RECURSOR_VERSION=$(PDNS_RECURSOR_VERSION) \
		--label org.opencontainers.image.created=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--tag "${CI_REGISTRY_IMAGE}:$(PDNS_RECURSOR_VERSION)" \
		--file Dockerfile .
	@echo "Built: pdns-rec-distroless:$(PDNS_RECURSOR_VERSION)"

build-debug: ## Build debug image with shell
	docker buildx build \
		--platform linux/arm64 \
		--build-arg PDNS_RECURSOR_VERSION=$(PDNS_RECURSOR_VERSION) \
		--label org.opencontainers.image.created=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--tag "${CI_REGISTRY_IMAGE}:$(PDNS_RECURSOR_VERSION)-debug" \
		--file Debug.Dockerfile .
	@echo "Built: pdns-rec-distroless:$(PDNS_RECURSOR_VERSION)-debug"

build: build-prod build-debug ## Build both production and debug images

test: ## Run basic test with docker compose
	docker compose up --build

verify: ## Verify built production image
	@echo "Verifying pdns-rec-distroless:$(PDNS_RECURSOR_VERSION)..."
	docker run --rm ${CI_REGISTRY_IMAGE}:$(PDNS_RECURSOR_VERSION) --version
	@echo "✓ Image verified successfully"

clean: ## Stop and remove all containers and volumes
	docker compose down -v

clean-images: ## Remove built images
	docker rmi ${CI_REGISTRY_IMAGE}:$(PDNS_RECURSOR_VERSION) || true
	docker rmi ${CI_REGISTRY_IMAGE}:$(PDNS_RECURSOR_VERSION)-debug || true
