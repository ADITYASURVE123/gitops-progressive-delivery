#!/bin/bash

# Chaos Engineering Script for GitOps Progressive Delivery
# This script injects failures to test automatic rollback behavior

set -e

CLUSTER_NAME="progressive-delivery"
NAMESPACE="app-monitoring"
SERVICE_NAME="api-service"
FAIL_RATE=0.5
ROLLBACK_TIMEOUT=180

log() {
    echo -e "\033[1;32m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

warn() {
    echo -e "\033[1;33m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl is not installed"
        exit 1
    fi

    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        error "Kind cluster $CLUSTER_NAME not found"
        exit 1
    fi

    log "Prerequisites check passed"
}

inject_failures() {
    log "Injecting failures with FAIL_RATE=$FAIL_RATE..."

    # Scale down to 1 pod to ensure we can inject failures
    kubectl -n $NAMESPACE scale deployment api-stable --replicas=1
    kubectl -n $NAMESPACE scale deployment api-canary --replicas=1

    # Set FAIL_RATE environment variable
    kubectl -n $NAMESPACE set env deployment/api-canary FAIL_RATE=$FAIL_RATE

    log "Failures injected successfully"
}

monitor_rollback() {
    log "Monitoring for automatic rollback..."

    local start_time=$(date +%s)
    local timeout=$((start_time + ROLLBACK_TIMEOUT))

    while [ $(date +%s) -lt $timeout ]; do
        # Check if rollout has been aborted
        local rollout_status=$(kubectl -n $NAMESPACE get rollout api-rollout-canary -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        if [ "$rollout_status" = "Aborted" ]; then
            log "✅ Rollout was aborted as expected"
            return 0
        fi

        sleep 10
    done

    error "Rollback timeout after ${ROLLBACK_TIMEOUT}s"
    return 1
}

verify_rollback() {
    log "Verifying rollback..."

    # Check that stable pods are running
    local stable_pods=$(kubectl -n $NAMESPACE get pods -l app=api,version=stable --no-headers | wc -l)

    if [ "$stable_pods" -eq 0 ]; then
        error "No stable pods found after rollback"
        return 1
    fi

    log "✅ Stable pods running: $stable_pods"

    # Verify canary pods are scaled down
    local canary_pods=$(kubectl -n $NAMESPACE get pods -l app=api,version=canary --no-headers | wc -l)

    if [ "$canary_pods" -gt 0 ]; then
        warn "Canary pods still running: $canary_pods"
    else
        log "✅ Canary pods scaled down"
    fi

    return 0
}

cleanup() {
    log "Cleaning up..."

    # Reset FAIL_RATE
    kubectl -n $NAMESPACE set env deployment/api-canary FAIL_RATE=0.0

    # Scale back to normal
    kubectl -n $NAMESPACE scale deployment api-stable --replicas=3
    kubectl -n $NAMESPACE scale deployment api-canary --replicas=3

    log "Cleanup completed"
}

main() {
    log "Starting chaos engineering test..."

    check_prerequisites
    inject_failures

    if monitor_rollback; then
        if verify_rollback; then
            log "✅ Chaos engineering test passed"
            cleanup
            exit 0
        fi
    fi

    error "❌ Chaos engineering test failed"
    cleanup
    exit 1
}

# Run main function
main "$@"