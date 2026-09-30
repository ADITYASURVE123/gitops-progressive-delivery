#!/bin/bash

# Bootstrap script for GitOps Progressive Delivery Platform
# This script sets up a local Kubernetes cluster with all required components

set -e

# Configuration
CLUSTER_NAME="progressive-delivery"
K8S_VERSION="v1.28.0"
ARGOCD_VERSION="v2.9.5"
ARGOROLLOUTS_VERSION="v1.5.1"
PROMETHEUS_STACK_VERSION="48.3.1"
NGINX_INGRESS_VERSION="4.8.0"

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies
install_dependencies() {
    log_info "Installing dependencies..."

    if command_exists apt-get; then
        log_info "Detected Debian/Ubuntu system"
        sudo apt-get update
        sudo apt-get install -y curl wget git unzip jq yaml-cli
    elif command_exists yum; then
        log_info "Detected RHEL/CentOS system"
        sudo yum update -y
        sudo yum install -y curl wget git unzip jq python3-yaml
    elif command_exists apk; then
        log_info "Detected Alpine system"
        sudo apk update
        sudo apk add curl wget git unzip jq
    else
        log_error "Unsupported package manager. Please install dependencies manually."
        exit 1
    fi

    if ! command_exists kind; then
        log_info "Installing Kind..."
        go install sigs.k8s.io/kind@latest
        export PATH="$PATH:$(go env GOPATH)/bin"
    fi

    if ! command_exists kubectl; then
        log_info "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    fi

    if ! command_exists helm; then
        log_info "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-2.sh -o get-helm.sh
        chmod +x get-helm.sh
        ./get-helm.sh --version v3.12.0
        rm get-helm.sh
    fi
}

# Function to create local Kubernetes cluster
create_cluster() {
    log_info "Creating Kind cluster: $CLUSTER_NAME"

    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        cat <<EOF | kind create cluster --name $CLUSTER_NAME --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 8080
    hostPort: 8080
    protocol: TCP
  - containerPort: 3000
    hostPort: 3000
    protocol: TCP
  - containerPort: 9090
    hostPort: 9090
    protocol: TCP
  - containerPort: 3003
    hostPort: 3003
    protocol: TCP
EOF
    else
        log_info "Cluster $CLUSTER_NAME already exists"
    fi

    # Configure kubectl
    kind export kubeconfig --name $CLUSTER_NAME
}

# Function to install Argo CD
install_argocd() {
    log_info "Installing Argo CD..."

    kubectl apply -f https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/manifests/install.yaml

    # Wait for Argo CD to be ready
    log_info "Waiting for Argo CD to be ready..."
    kubectl -n argocd wait deployment argocd-server --for condition=available --timeout=300s

    # Get initial admin password
    log_info "Getting initial Argo CD admin password..."
    ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
    echo "Argo CD Admin Password: $ADMIN_PASSWORD"
    echo "Please store this password for initial login"
}

# Function to install Argo Rollouts
install_argorollouts() {
    log_info "Installing Argo Rollouts..."

    kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/download/v${ARGOROLLOUTS_VERSION}/install.yaml

    # Wait for Argo Rollouts to be ready
    log_info "Waiting for Argo Rollouts to be ready..."
    kubectl -n argo-rollouts wait deployment rollout-controller --for condition=available --timeout=300s
}

# Function to install Prometheus Stack
install_prometheus_stack() {
    log_info "Installing Prometheus Stack..."

    kubectl create namespace monitoring

    # Install Prometheus Operator
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/release-0.67/manifests/prometheus-operator.yaml

    # Install Prometheus CRDs
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/release-0.67/manifests/setup/prometheus-operator-crd.yaml

    # Install kube-prometheus-stack
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    helm install prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --version ${PROMETHEUS_STACK_VERSION} \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplates[0].spec.storageClassName=local-storage \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplates[0].spec.resources.requests.storage=50Gi \
        --set grafana.adminPassword=admin123 \
        --set prometheus-node-exporter.enabled=true \
        --set kube-state-metrics.enabled=true

    # Wait for components to be ready
    log_info "Waiting for Prometheus Stack to be ready..."
    kubectl -n monitoring wait deployment prometheus-stack-operator --for condition=available --timeout=300s
    kubectl -n monitoring wait deployment prometheus-stack-prometheus --for condition=available --timeout=300s
    kubectl -n monitoring wait deployment grafana --for condition=available --timeout=300s
}

# Function to install Nginx Ingress
install_ingress() {
    log_info "Installing Nginx Ingress Controller..."

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

    # Wait for Ingress Controller to be ready
    log_info "Waiting for Nginx Ingress Controller to be ready..."
    kubectl -n ingress-nginx wait deployment ingress-nginx-controller --for condition=available --timeout=300s
}

# Function to install cert-manager (for TLS)
install_cert_manager() {
    log_info "Installing cert-manager..."

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

    # Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."
    kubectl -n cert-manager wait deployment cert-manager --for condition=available --timeout=300s
    kubectl -n cert-manager wait deployment cert-manager-cainjector --for condition=available --timeout=300s
}

# Function to create namespaces
create_namespaces() {
    log_info "Creating required namespaces..."

    kubectl create namespace argocd
    kubectl create namespace argo-rollouts
    kubectl create namespace app-monitoring
    kubectl create namespace ingress-nginx
    kubectl create namespace cert-manager
    kubectl create namespace monitoring
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."

    # Check if all components are running
    log_info "Checking component status..."

    # Argo CD
    if kubectl -n argocd get deployment argocd-server --ignore-not-found; then
        log_info "✅ Argo CD is running"
    else
        log_error "❌ Argo CD is not running"
    fi

    # Argo Rollouts
    if kubectl -n argo-rollouts get deployment rollout-controller --ignore-not-found; then
        log_info "✅ Argo Rollouts is running"
    else
        log_error "❌ Argo Rollouts is not running"
    fi

    # Prometheus Stack
    if kubectl -n monitoring get deployment prometheus-stack-prometheus --ignore-not-found; then
        log_info "✅ Prometheus is running"
    else
        log_error "❌ Prometheus is not running"
    fi

    # Grafana
    if kubectl -n monitoring get deployment grafana --ignore-not-found; then
        log_info "✅ Grafana is running"
    else
        log_error "❌ Grafana is not running"
    fi

    # Nginx Ingress
    if kubectl -n ingress-nginx get deployment ingress-nginx-controller --ignore-not-found; then
        log_info "✅ Nginx Ingress is running"
    else
        log_error "❌ Nginx Ingress is not running"
    fi

    # cert-manager
    if kubectl -n cert-manager get deployment cert-manager --ignore-not-found; then
        log_info "✅ cert-manager is running"
    else
        log_error "❌ cert-manager is not running"
    fi

    log_info "Installation verification complete"
}

# Function to display completion message
completion_message() {
    log_info "Installation complete!"
    echo ""
    echo "========================================="
    echo "GitOps Progressive Delivery Platform Setup"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Access Argo CD: kubectl port-forward svc/argocd-server -n argocd 8080:80"
    echo "2. Login with username: admin, password: $ADMIN_PASSWORD"
    echo "3. Access Grafana: kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80"
    echo "4. Login with username: admin, password: admin123"
    echo "5. Access Prometheus: kubectl port-forward svc/prometheus-stack-prometheus -n monitoring 9090:9090"
    echo ""
    echo "Useful commands:"
    echo "- View all resources: kubectl get all --all-namespaces"
    echo "- Check Argo CD applications: kubectl get applications --all-namespaces"
    echo "- Check rollouts: kubectl get rollouts --all-namespaces"
    echo "- Port forward to API service: kubectl port-forward svc/api-service -n app-monitoring 8080:8080"
    echo ""
}

# Main execution
main() {
    log_info "Starting GitOps Progressive Delivery Platform bootstrap..."

    # Check for required tools
    if ! command_exists kind; then
        log_warn "Kind not found, installing..."
        install_dependencies
    fi

    # Create cluster
    create_cluster

    # Create namespaces
    create_namespaces

    # Install components
    install_argocd
    install_argorollouts
    install_prometheus_stack
    install_ingress
    install_cert_manager

    # Verify installation
    verify_installation

    # Display completion message
    completion_message

    log_info "Bootstrap script completed successfully!"
}

# Run main function
main "$@"