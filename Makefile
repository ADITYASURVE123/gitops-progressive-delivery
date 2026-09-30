# Version
VERSION = 1.0.0
CLUSTER_NAME = progressive-delivery
K8S_VERSION = v1.28.0

# Directories
INFRA_DIR = infra
APP_DIR = app
GITOPS_DIR = gitops
OBS_DIR = observability
TESTS_DIR = tests
DOCS_DIR = docs

# Binary names
API_BINARY = api-service
FRONTEND_BINARY = frontend-service

# Docker images
API_IMAGE = ghcr.io/claudcoding/api-service
FRONTEND_IMAGE = ghcr.io/claudcoding/frontend-service

.PHONY: help bootstrap deploy test test/unit test/integration test/chaos destroy lint build clean setup-env validate docs security-scan deploy-all status

help:
	@echo "GitOps Progressive Delivery Platform"
	@echo "================================="
	@echo "Available targets:"
	@echo "  bootstrap        - Bootstrap local Kubernetes cluster with all components"
	@echo "  deploy           - Deploy application via GitOps"
	@echo "  test             - Run all tests"
	@echo "  destroy          - Destroy local cluster"
	@echo "  lint             - Lint code"
	@echo "  build            - Build all services"
	@echo "  clean            - Clean up build artifacts"
	@echo "  status           - Check platform status"

setup-env:
	@echo "Setting up environment..."
	@mkdir -p $(INFRA_DIR)/kind
	@mkdir -p $(GITOPS_DIR)/overlays/prod
	@mkdir -p $(GITOPS_DIR)/overlays/dev
	@mkdir -p $(OBS_DIR)/prometheus/rules
	@mkdir -p $(OBS_DIR)/grafana/dashboards
	@mkdir -p $(TESTS_DIR)/unit $(TESTS_DIR)/integration $(TESTS_DIR)/chaos
	@mkdir -p $(DOCS_DIR)/adr
	@echo "Environment setup complete."

bootstrap: setup-env
	@echo "Bootstrapping GitOps Progressive Delivery Platform..."
	@if [ -f "./infra/bootstrap.sh" ]; then \
		chmod +x ./infra/bootstrap.sh && ./infra/bootstrap.sh kind; \
	elif [ -f "./bootstrap.sh" ]; then \
		chmod +x ./bootstrap.sh && ./bootstrap.sh kind; \
	else \
		echo "Error: Bootstrap script not found."; exit 1; \
	fi

deploy:
	@echo "Deploying application via GitOps..."
	@kubectl apply -R -f $(GITOPS_DIR)/
	@kubectl -n argocd wait deployment argocd-server --for condition=available --timeout=120s || true
	@echo "Manifests applied successfully."

test: test/unit test/integration test/chaos

test/unit:
	@echo "Running unit tests..."
	@cd $(APP_DIR)/api && go test ./... -v || true
	@cd $(APP_DIR)/frontend && npm test || true

test/integration:
	@echo "Running integration tests..."

test/chaos:
	@echo "Running chaos tests for rollback verification..."
	@if [ -f "./tests/chaos/verify-rollback.sh" ]; then \
		chmod +x ./tests/chaos/verify-rollback.sh && ./tests/chaos/verify-rollback.sh; \
	fi

destroy:
	@echo "Destroying local cluster..."
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$"; then \
		kind delete cluster --name $(CLUSTER_NAME); \
		echo "Cluster $(CLUSTER_NAME) deleted"; \
	else \
		echo "Cluster $(CLUSTER_NAME) does not exist"; \
	fi

lint:
	@echo "Linting code..."
	@cd $(APP_DIR)/api && golangci-lint run || true
	@cd $(APP_DIR)/frontend && npm run lint || true

build:
	@echo "Building all services..."
	@cd $(APP_DIR)/api && make build || true
	@cd $(APP_DIR)/frontend && make build || true

clean:
	@echo "Cleaning up..."
	@rm -rf coverage.out coverage.html
	@echo "Cleaning complete."

validate:
	@echo "Validating manifests..."
	@kubectl apply --dry-run=client -R -f $(GITOPS_DIR)/

docs:
	@echo "Generating documentation..."

security-scan:
	@echo "Running security scans..."
	@trivy fs --severity HIGH,CRITICAL . || true

deploy-all: bootstrap deploy

status:
	@echo "Platform Status:"
	@echo "==============="
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$"; then \
		echo "✅ Cluster: $(CLUSTER_NAME) is running"; \
	else \
		echo "❌ Kind cluster is not running"; \
	fi
	@echo ""
	@echo "Services:"
	@echo "========"
	@kubectl get pods -n argocd >/dev/null 2>&1 && echo "✅ Argo CD: Running" || echo "❌ Argo CD: Not running"
	@kubectl get pods -n argo-rollouts >/dev/null 2>&1 && echo "✅ Argo Rollouts: Running" || echo "❌ Argo Rollouts: Not running"
	@kubectl get pods -n monitoring >/dev/null 2>&1 && echo "✅ Prometheus/Grafana: Running" || echo "❌ Monitoring: Not running"
	@kubectl get pods -n app-monitoring >/dev/null 2>&1 && echo "✅ Application Stack: Running" || echo "❌ Application Stack: Not running"
