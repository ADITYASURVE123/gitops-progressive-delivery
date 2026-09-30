# Makefile for GitOps Progressive Delivery Platform

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

# Default target
.PHONY: help

help:
	@echo "GitOps Progressive Delivery Platform"
	@echo "================================="
	@echo "Available targets:"
	@echo "  bootstrap    - Bootstrap local Kubernetes cluster with all components"
	@echo "  deploy       - Deploy application via GitOps"
	@echo "  test         - Run all tests"
	@echo "  test/unit    - Run unit tests"
	@echo "  test/integration - Run integration tests"
	@echo "  test/chaos    - Run chaos testing for rollback verification"
	@echo "  destroy      - Destroy local cluster"
	@echo "  lint         - Lint code"
	@echo "  build        - Build all services"
	@echo "  clean        - Clean up build artifacts"
	@echo ""
	@echo "Configuration options:"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME) - Name of the Kind cluster"
	@echo "  API_IMAGE=$(API_IMAGE) - API Docker image"
	@echo "  FRONTEND_IMAGE=$(FRONTEND_IMAGE) - Frontend Docker image"

.PHONY: bootstrap
bootstrap:
	@echo "Bootstrapping GitOps Progressive Delivery Platform..."
	@chmod +x bootstrap.sh
	@./bootstrap.sh

.PHONY: deploy

deploy:
	@echo "Deploying application via GitOps..."
	@echo "Step 1: Apply GitOps manifests..."
	@echo "Step 2: Sync applications with Argo CD..."
	@echo "Step 3: Verify rollout..."
	@echo "To deploy manually, run:"
	@echo "  kubectl apply -f gitops/"
	@echo "  kubectl -n argocd wait deployment argocd-server --for condition=available"
	@echo ""
	@echo "Check deployment status:"
	@echo "  kubectl get applications --all-namespaces"
	@echo "  kubectl get rollouts --all-namespaces"
	@echo "  kubectl get pods --all-namespaces"

.PHONY: test
test: test/unit test/integration test/chaos

.PHONY: test/unit
test/unit:
	@echo "Running unit tests..."
	@echo "Unit tests would run here"
	@echo "  cd $(APP_DIR)/api && go test ./... -v"
	@echo "  cd $(APP_DIR)/frontend && npm test"

.PHONY: test/integration
test/integration:
	@echo "Running integration tests..."
	@echo "Integration tests would run here"
	@echo "  Testing API endpoints, services, and GitOps integration"

.PHONY: test/chaos
test/chaos:
	@echo "Running chaos tests for rollback verification..."
	@echo "Chaos tests would run here"
	@echo "  Testing automatic rollback on failures"

.PHONY: destroy
destroy:
	@echo "Destroying local cluster..."
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$"; then \
		kind delete cluster --name $(CLUSTER_NAME); \
		echo "Cluster $(CLUSTER_NAME) deleted"; \
	else \
		echo "Cluster $(CLUSTER_NAME) does not exist"; \
	fi

.PHONY: lint
lint:
	@echo "Linting code..."
	@echo "Linting would run here"
	@echo "  cd $(APP_DIR)/api && golangci-lint run"
	@echo "  cd $(APP_DIR)/frontend && eslint src/"

.PHONY: build
build:
	@echo "Building all services..."
	@echo "Building API service..."
	@cd $(APP_DIR)/api && make build
	@echo "Building frontend service..."
	@cd $(APP_DIR)/frontend && make build
	@echo "Building Docker images..."
	@echo "Docker builds would run here"

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@cd $(APP_DIR)/api && make clean
	@cd $(APP_DIR)/frontend && make clean
	@echo "Removing build artifacts..."
	@rm -rf coverage.out coverage.html
	@rm -rf $(APP_DIR)/api/$(API_BINARY)
	@echo "Cleaning complete."

.PHONY: setup-env
setup-env:
	@echo "Setting up environment..."
	@echo "Creating required directories..."
	@mkdir -p $(INFRA_DIR)/kind
	@mkdir -p $(GITOPS_DIR)/overlays/prod
	@mkdir -p $(GITOPS_DIR)/overlays/dev
	@mkdir -p $(OBS_DIR)/prometheus/rules
	@mkdir -p $(OBS_DIR)/grafana/dashboards
	@mkdir -p $(TESTS_DIR)/unit
	@mkdir -p $(TESTS_DIR)/integration
	@mkdir -p $(TESTS_DIR)/chaos
	@mkdir -p $(DOCS_DIR)/adr
	@echo "Environment setup complete."

.PHONY: validate
validate:
	@echo "Validating manifests..."
	@echo "Validating GitOps manifests..."
	@cd $(GITOPS_DIR) && kustomize build . > /dev/null || (echo "GitOps manifests validation failed"; exit 1)
	@echo "Validating API service..."
	@cd $(APP_DIR)/api && go build ./... > /dev/null || (echo "API service validation failed"; exit 1)
	@echo "Validation complete."

.PHONY: docs
	docs:
	@echo "Generating documentation..."
	@echo "Documentation generation would run here"
	@echo "  Generating API documentation"
	@echo "  Generating architecture documentation"
	@echo "  Generating setup documentation"

.PHONY: security-scan
security-scan:
	@echo "Running security scans..."
	@echo "Security scans would run here"
	@echo "  Scanning API dependencies"
	@echo "  Scanning frontend dependencies"
	@echo "  Scanning infrastructure code"

.PHONY: deploy-all
deploy-all: bootstrap deploy

.PHONY: status
status:
	@echo "Platform Status:"
	@echo "==============="
	@if command -v kind >/dev/null 2>&1; then \
		if kind get clusters | grep -q "^$(CLUSTER_NAME)$"; then \
			echo "✅ Cluster: $(CLUSTER_NAME) is running"; \
			echo "$(kind get nodes --name $(CLUSTER_NAME) | xargs -I {} kubectl get nodes {} --template '{{.metadata.name}}: {{.status.conditions[-1].type}}' 2>/dev/null || echo "  (kubectl not available)"; fi; fi; \
	else \
		echo "❌ Kind cluster manager not installed"; fi
	@echo ""
	@echo "Services:"
	@echo "========"
	@if kubectl get namespace argocd --ignore-not-found >/dev/null 2>&1; then \
		if kubectl -n argocd get deployment argocd-server --ignore-not-found >/dev/null 2>&1; then \
			echo "✅ Argo CD: Running"; else echo "❌ Argo CD: Not running"; fi; else echo "❌ Argo CD: Namespace not found"; fi
	@if kubectl get namespace argo-rollouts --ignore-not-found >/dev/null 2>&1; then \
		if kubectl -n argo-rollouts get deployment rollout-controller --ignore-not-found >/dev/null 2>&1; then \
			echo "✅ Argo Rollouts: Running"; else echo "❌ Argo Rollouts: Not running"; fi; else echo "❌ Argo Rollouts: Namespace not found"; fi
	@if kubectl get namespace monitoring --ignore-not-found >/dev/null 2>&1; then \
		if kubectl -n monitoring get deployment prometheus-stack-prometheus --ignore-not-found >/dev/null 2>&1; then \
			echo "✅ Prometheus: Running"; else echo "❌ Prometheus: Not running"; fi; else echo "❌ Prometheus: Namespace not found"; fi
	@if kubectl get namespace app-monitoring --ignore-not-found >/dev/null 2>&1; then \
		if kubectl -n app-monitoring get deployment $(API_BINARY) --ignore-not-found >/dev/null 2>&1; then \
			echo "✅ API Service: Running"; else echo "❌ API Service: Not running"; fi; else echo "❌ API Service: Namespace not found"; fi
	@if kubectl get namespace app-monitoring --ignore-not-found >/dev/null 2>&1; then \
		if kubectl -n app-monitoring get deployment $(FRONTEND_BINARY) --ignore-not-found >/dev/null 2>&1; then \
			echo "✅ Frontend Service: Running"; else echo "❌ Frontend Service: Not running"; fi; else echo "❌ Frontend Service: Namespace not found"; fi
	@echo ""
	@echo "Usage Examples:"
	@echo "============="
	@echo "  make deploy    - Deploy application via GitOps"
	@echo "  make test      - Run all tests"
	@echo "  make destroy   - Destroy local cluster"
	@echo "  make status    - Check platform status"
	@echo ""
	@echo "After deployment, access services:"
	@echo "  API Service:    kubectl port-forward svc/api-service -n app-monitoring 8080:8080"
	@echo "  Frontend Service: kubectl port-forward svc/frontend-service -n app-monitoring 3000:3000"
	@echo "  Grafana: kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80"
	@echo "  Prometheus: kubectl port-forward svc/prometheus-stack-prometheus -n monitoring 9090:9090"
	@echo ""
	@echo "To clean up: make destroy"