#!/bin/bash
# =============================================================================
# SRE Health Check Script - Online Boutique
# =============================================================================
# WHAT: Validates all deployed services are healthy
# WHEN: Run after deployment, during incident response, or via cron
# WHO:  SRE / Platform Engineer / On-Call Engineer
#
# Usage:
#   ./scripts/health-check.sh                    # Check all services
#   ./scripts/health-check.sh frontend           # Check specific service
#   ./scripts/health-check.sh --namespace staging # Check specific namespace
# =============================================================================

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-default}"
TARGET_SERVICE="${1:-all}"
FAILURES=0
TOTAL=0

# =============================================================================
# Helper Functions
# =============================================================================

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[  OK]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $1"; FAILURES=$((FAILURES + 1)); }

header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# =============================================================================
# Check 1: Pod Health — Are all pods Running and Ready?
# =============================================================================
check_pods() {
    header "POD HEALTH CHECK"

    local services=("frontend" "productcatalogservice" "cartservice" "redis-cart" "currencyservice")

    for svc in "${services[@]}"; do
        if [ "$TARGET_SERVICE" != "all" ] && [ "$TARGET_SERVICE" != "$svc" ]; then
            continue
        fi

        TOTAL=$((TOTAL + 1))
        local status=$(kubectl get pods -n "$NAMESPACE" -l app="$svc" \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        local ready=$(kubectl get pods -n "$NAMESPACE" -l app="$svc" \
            -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

        if [ "$status" == "Running" ] && [ "$ready" == "True" ]; then
            log_ok "$svc — Running & Ready"
        elif [ -z "$status" ]; then
            log_fail "$svc — Pod NOT FOUND"
        else
            log_fail "$svc — Status: $status, Ready: $ready"
        fi
    done
}

# =============================================================================
# Check 2: Service Endpoints — Do services have active endpoints?
# =============================================================================
check_endpoints() {
    header "SERVICE ENDPOINT CHECK"

    local services=("frontend" "productcatalogservice" "cartservice" "redis-cart")

    for svc in "${services[@]}"; do
        if [ "$TARGET_SERVICE" != "all" ] && [ "$TARGET_SERVICE" != "$svc" ]; then
            continue
        fi

        TOTAL=$((TOTAL + 1))
        local endpoints=$(kubectl get endpoints "$svc" -n "$NAMESPACE" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)

        if [ -n "$endpoints" ]; then
            log_ok "$svc — Endpoints: $endpoints"
        else
            log_fail "$svc — NO active endpoints (service is unreachable!)"
        fi
    done
}

# =============================================================================
# Check 3: Resource Usage — Are pods near their limits?
# =============================================================================
check_resources() {
    header "RESOURCE USAGE CHECK"

    TOTAL=$((TOTAL + 1))
    if kubectl top pods -n "$NAMESPACE" > /dev/null 2>&1; then
        echo ""
        kubectl top pods -n "$NAMESPACE" --sort-by=memory 2>/dev/null || true
        echo ""
        log_ok "Metrics server is available"
    else
        log_warn "Metrics server not available (install metrics-server for resource monitoring)"
    fi
}

# =============================================================================
# Check 4: Recent Events — Any warnings or errors?
# =============================================================================
check_events() {
    header "RECENT CLUSTER EVENTS (Last 10 warnings)"

    TOTAL=$((TOTAL + 1))
    local warnings=$(kubectl get events -n "$NAMESPACE" \
        --field-selector type=Warning \
        --sort-by='.lastTimestamp' 2>/dev/null | tail -10)

    if [ -z "$warnings" ] || [ "$warnings" == "No resources found in $NAMESPACE namespace." ]; then
        log_ok "No warning events in namespace '$NAMESPACE'"
    else
        log_warn "Warning events detected:"
        echo "$warnings"
    fi
}

# =============================================================================
# Check 5: Deployment Rollout Status
# =============================================================================
check_rollout() {
    header "DEPLOYMENT ROLLOUT STATUS"

    local deployments=$(kubectl get deployments -n "$NAMESPACE" \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    for deploy in $deployments; do
        if [ "$TARGET_SERVICE" != "all" ] && [ "$TARGET_SERVICE" != "$deploy" ]; then
            continue
        fi

        TOTAL=$((TOTAL + 1))
        local desired=$(kubectl get deployment "$deploy" -n "$NAMESPACE" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null)
        local available=$(kubectl get deployment "$deploy" -n "$NAMESPACE" \
            -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        available=${available:-0}

        if [ "$desired" == "$available" ]; then
            log_ok "$deploy — $available/$desired replicas available"
        else
            log_fail "$deploy — $available/$desired replicas (DEGRADED!)"
        fi
    done
}

# =============================================================================
# Main Execution
# =============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     SRE Health Check — Online Boutique           ║${NC}"
echo -e "${GREEN}║     Namespace: $NAMESPACE                              ║${NC}"
echo -e "${GREEN}║     Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"

check_pods
check_endpoints
check_resources
check_events
check_rollout

# =============================================================================
# Summary
# =============================================================================
header "HEALTH CHECK SUMMARY"

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✅ ALL CHECKS PASSED ($TOTAL/$TOTAL)${NC}"
    echo -e "${GREEN}   System is healthy and serving traffic${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILURES CHECKS FAILED out of $TOTAL${NC}"
    echo -e "${RED}   Investigate failed services immediately${NC}"
    echo ""
    echo -e "${YELLOW}🔍 Debugging tips:${NC}"
    echo "   kubectl describe pod <pod-name>    # See events & errors"
    echo "   kubectl logs <pod-name>            # See application logs"
    echo "   kubectl get events --sort-by='.lastTimestamp'  # Recent events"
    exit 1
fi
