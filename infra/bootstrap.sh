#!/bin/bash

# Infrastructure Setup Script for GitOps Progressive Delivery Platform
# This script provides infrastructure setup options for different environments

set -e

CLUSTER_NAME="progressive-delivery"
K8S_VERSION="v1.28.0"
ARGOCD_VERSION="v2.9.5"
ARGOROLLOUTS_VERSION="v1.5.1"
PROMETHEUS_STACK_VERSION="48.3.1"
NGINX_INGRESS_VERSION="4.8.0"
CERT_MANAGER_VERSION="v1.13.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to setup kind cluster
setup_kind() {
    log_info "Setting up Kind cluster..."

    if command_exists kind; then
        if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
            log_info "Creating Kind cluster: $CLUSTER_NAME"
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
            kind export kubeconfig --name $CLUSTER_NAME
        else
            log_info "Cluster $CLUSTER_NAME already exists"
        fi
    else
        log_error "Kind is not installed"
        exit 1
    fi
}

# Function to setup GKE cluster
setup_gke() {
    log_info "Setting up GKE cluster..."

    if ! command_exists gcloud; then
        log_error "Google Cloud SDK is not installed"
        exit 1
    fi

    # Configure GCP project (using default for demo)
    gcloud config set project "demo-project-$CLUSTER_NAME"

    # Create GKE cluster
    log_info "Creating GKE cluster: $CLUSTER_NAME"
    gcloud container clusters create $CLUSTER_NAME \
        --zone us-central1-a \
        --release-channel=stable \
        --enable-master-authorized-networks \
        --enable-ip-alias \
        --enable-network-policy \
        --enable-horizontal-pod-autoscaling \
        --enable-vertical-pod-autoscaling \
        --preemptible \
        --no-enable-private-endpoint

    # Get cluster credentials
    gcloud container clusters get-credentials $CLUSTER_NAME --zone us-central1-a
}

# Function to setup AWS EKS cluster
setup_eks() {
    log_info "Setting up AWS EKS cluster..."

    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured"
        exit 1
    fi

    # Create EKS cluster
    log_info "Creating EKS cluster: $CLUSTER_NAME"
    eksctl create cluster \
        --name $CLUSTER_NAME \
        --region us-central-1 \
        --node-type t3.medium \
        --nodes 3 \
        --zones us-central-1a,us-central-1b,us-central-1c \
        --managed \
        --without-nodegroup \
        --asg-access \
        --external-dns-access \
        --full-ecr-access \
        --appmesh-access

    # Update kubeconfig
    aws eks update-kubeconfig --name $CLUSTER_NAME --region us-central-1
}

# Function to install essential components
setup_components() {
    log_info "Setting up cluster components..."

    # Create namespaces
    log_info "Creating namespaces..."
    kubectl create namespace argocd || true
    kubectl create namespace argo-rollouts || true
    kubectl create namespace app-monitoring || true
    kubectl create namespace ingress-nginx || true
    kubectl create namespace cert-manager || true
    kubectl create namespace monitoring || true

    # Install cert-manager for TLS
    log_info "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml
    kubectl -n cert-manager wait deployment cert-manager --for condition=available --timeout=300s
    kubectl -n cert-manager wait deployment cert-manager-cainjector --for condition=available --timeout=300s

    # Install Nginx Ingress
    log_info "Installing Nginx Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    kubectl -n ingress-nginx wait deployment ingress-nginx-controller --for condition=available --timeout=300s

    # Install Argo CD
    log_info "Installing Argo CD..."
    kubectl apply -f https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/manifests/install.yaml
    kubectl -n argocd wait deployment argocd-server --for condition=available --timeout=300s

    # Install Argo Rollouts
    log_info "Installing Argo Rollouts..."
    kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/download/v${ARGOROLLOUTS_VERSION}/install.yaml
    kubectl -n argo-rollouts wait deployment rollout-controller --for condition=available --timeout=300s

    # Install Prometheus Stack
    log_info "Installing Prometheus Stack..."
    kubectl create namespace monitoring
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/release-0.67/manifests/prometheus-operator.yaml
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/release-0.67/manifests/setup/prometheus-operator-crd.yaml

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
    log_info "Waiting for components to be ready..."
    kubectl -n monitoring wait deployment prometheus-stack-operator --for condition=available --timeout=300s
    kubectl -n monitoring wait deployment prometheus-stack-prometheus --for condition=available --timeout=300s
    kubectl -n monitoring wait deployment grafana --for condition=available --timeout=300s

    # Setup GitOps manifests
    setup_gitops_manifests
}

# Function to setup GitOps manifests
setup_gitops_manifests() {
    log_info "Setting up GitOps manifests..."

    # Create gitops directory structure
    mkdir -p gitops/overlays/prod
    mkdir -p gitops/overlays/dev
    mkdir -p gitops/base
    mkdir -p gitops/apps

    # Setup base manifests (simplified versions)
    log_info "Setting up base GitOps manifests..."

    # Create base manifests directory
    mkdir -p gitops/base

    # Create app-of-apps.yaml
    cat > gitops/apps/app-of-apps.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ClaudCoding/gitops-progressive-delivery
    targetRevision: main
    path: gitops/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: app-monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        maxDuration: 60s
EOF

    # Create deployment examples
    mkdir -p gitops/base
    cat > gitops/base/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
  labels:
    app: api-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-service
  template:
    metadata:
      labels:
        app: api-service
    spec:
      containers:
      - name: api
        image: ghcr.io/claudcoding/api-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        - name: FAIL_RATE
          value: "0.0"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

    # Create service.yaml
    cat > gitops/base/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api-service
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

    log_info "GitOps manifests setup completed"
}

# Function to deploy demo application
deploy_demo() {
    log_info "Deploying demo application..."

    # Create app-monitoring namespace
    kubectl create namespace app-monitoring || true

    # Deploy API service
    kubectl -n app-monitoring apply -f gitops/base/deployment.yaml
    kubectl -n app-monitoring apply -f gitops/base/service.yaml

    # Wait for deployment
    log_info "Waiting for API service to be ready..."
    kubectl -n app-monitoring wait deployment/api-service --for condition=available --timeout=300s

    # Expose service via Ingress
    kubectl -n app-monitoring apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: app-monitoring
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
EOF

    log_info "Demo application deployed successfully"
}

# Function to setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring stack..."

    # Create monitoring namespace
    kubectl create namespace monitoring || true

    # Deploy Prometheus
    kubectl -n monitoring apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
spec:
  serviceAccountName: prometheus
  serviceMonitorSelector:
    matchLabels:
      app: api-service
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
EOF

    # Create Grafana dashboard
    kubectl -n monitoring apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard
  namespace: monitoring
data:
  rollout-dashboard.json: |
    {
      "dashboard": {
        "title": "GitOps Progressive Delivery",
        "panels": [],
        "refresh": "30s"
      }
    }
EOF

    log_info "Monitoring setup completed"
}

# Function to verify setup
verify_setup() {
    log_info "Verifying setup..."

    # Check cluster components
    log_info "Checking cluster components..."

    if kubectl -n argocd get deployment argocd-server --ignore-not-found >/dev/null 2>&1; then
        log_info "✅ Argo CD is running"
    else
        warn "❌ Argo CD is not running"
    fi

    if kubectl -n argo-rollouts get deployment rollout-controller --ignore-not-found >/dev/null 2>&1; then
        log_info "✅ Argo Rollouts is running"
    else
        warn "❌ Argo Rollouts is not running"
    fi

    if kubectl -n monitoring get deployment prometheus-stack-prometheus --ignore-not-found >/dev/null 2>&1; then
        log_info "✅ Prometheus is running"
    else
        warn "❌ Prometheus is not running"
    fi

    if kubectl -n monitoring get deployment grafana --ignore-not-found >/dev/null 2>&1; then
        log_info "✅ Grafana is running"
    else
        warn "❌ Grafana is not running"
    fi

    if kubectl -n app-monitoring get deployment api-service --ignore-not-found >/dev/null 2>&1; then
        log_info "✅ API Service is running"
    else
        warn "❌ API Service is not running"
    fi

    log_info "Setup verification completed"
}

# Function to display help
help() {
    echo "Infrastructure Setup Script for GitOps Progressive Delivery Platform"
    echo "=============================================="
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  kind      Setup with Kind (local Kubernetes)"
    echo "  gke       Setup with Google Kubernetes Engine (GKE)"
    echo "  eks       Setup with Amazon Elastic Kubernetes Service (EKS)"
    echo "  demo      Setup and deploy demo application"
    echo "  help      Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  CLUSTER_NAME     Name of the cluster (default: progressive-delivery)"
    echo "  K8S_VERSION      Kubernetes version (default: v1.28.0)"
    echo ""
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        help
        exit 1
    fi

    case $1 in
        kind)
            setup_kind
            setup_components
            deploy_demo
            setup_monitoring
            verify_setup
            completion_message
            ;;
        gke)
            setup_gke
            setup_components
            deploy_demo
            setup_monitoring
            verify_setup
            completion_message
            ;;
        eks)
            setup_eks
            setup_components
            deploy_demo
            setup_monitoring
            verify_setup
            completion_message
            ;;
        demo)
            setup_components
            deploy_demo
            setup_monitoring
            verify_setup
            completion_message
            ;;
        help)
            help
            ;;
        *)
            echo "Invalid option: $1"
            help
            exit 1
            ;;
    esac
}

# Function to display completion message
completion_message() {
    log_info "Infrastructure setup completed!"
    echo ""
    echo "========================================="
    echo "GitOps Progressive Delivery Platform Setup"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Access Argo CD: kubectl -n argocd port-forward svc/argocd-server 8080:80"
    echo "2. Login with username: admin"
    echo "3. Access Grafana: kubectl -n monitoring port-forward svc/prometheus-stack-grafana 3000:80"
    echo "4. Login with username: admin, password: admin123"
    echo "5. Access Prometheus: kubectl -n monitoring port-forward svc/prometheus-stack-prometheus 9090:9090"
    echo ""
    echo "Useful commands:"
    echo "- View all resources: kubectl get all --all-namespaces"
    echo "- Check Argo CD applications: kubectl get applications --all-namespaces"
    echo "- Check rollouts: kubectl get rollouts --all-namespaces"
    echo "- Port forward to API service: kubectl -n app-monitoring port-forward svc/api-service 8080:8080"
    echo ""
}

# Run main function
main "$@"