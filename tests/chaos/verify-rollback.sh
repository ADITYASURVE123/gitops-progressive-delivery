#!/bin/bash

# Rollback Verification Script
# Verifies that automatic rollback works correctly

set -e

CLUSTER_NAME="progressive-delivery"
NAMESPACE="app-monitoring"
SERVICE_NAME="api-service"
TIMEOUT=300

log() {
    echo -e "\033[1;32m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

warn() {
    echo -e "\033[1;33m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

check_cluster() {
    log "Checking cluster connectivity..."

    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to cluster"
        exit 1
    fi

    log "Cluster connectivity confirmed"
}

check_rollout_status() {
    local rollout_name=$1
    local expected_phase=$2

    log "Checking rollout status for $rollout_name..."

    local phase=$(kubectl -n $NAMESPACE get rollout $rollout_name -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [ "$phase" = "$expected_phase" ]; then
        log "✅ Rollout $rollout_name is $expected_phase"
        return 0
    else
        error "Rollout $rollout_name is $phase, expected $expected_phase"
        return 1
    fi
}

verify_traffic_distribution() {
    log "Verifying traffic distribution..."

    # Check that stable service has all traffic
    local stable_requests=$(kubectl -n $NAMESPACE logs -l app=api,version=stable --tail=1 2>/dev/null | grep -c "GET /health" || echo 0)
    local canary_requests=$(kubectl -n $NAMESPACE logs -l app=api,version=canary --tail=1 2>/dev/null | grep -c "GET /health" || echo 0)

    log "Stable requests: $stable_requests, Canary requests: $canary_requests"

    if [ "$canary_requests" -gt 0 ]; then
        warn "Canary service still receiving traffic"
    else
        log "✅ All traffic routed to stable service"
    fi
}

verify_health() {
    log "Verifying service health..."

    # Check that health endpoint returns 200
    local health_status=$(kubectl -n $NAMESPACE exec deploy/api-stable -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")

    if [ "$health_status" = "200" ]; then
        log "✅ Health check passed"
    else
        error "Health check failed with status $health_status"
        return 1
    fi
}

main() {
    log "Starting rollback verification..."

    check_cluster

    # Verify rollout status
    if ! check_rollout_status "api-rollout-canary" "Aborted"; then
        error "Rollout not aborted"
        exit 1
    fi

    if ! check_rollout_status "api-rollout-bluegreen" "Healthy"; then
        error "Rollout not healthy"
        exit 1
    fi

    # Verify traffic distribution
    verify_traffic_distribution

    # Verify service health
    verify_health

    log "✅ Rollback verification completed successfully"
}

# Run main function
main "$@"