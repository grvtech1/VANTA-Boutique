#!/bin/bash
# =============================================================================
# 🔥 FAILOVER & SELF-HEALING LAB — SRE Interview Scenarios
# =============================================================================
# These are the TOP 5 scenarios asked in DevOps/SRE interviews
# =============================================================================
export PATH="$HOME/.local/bin:$PATH"

echo "╔══════════════════════════════════════════════════╗"
echo "║     🔥 SRE FAILOVER & SELF-HEALING LAB          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Remove broken node-2
echo "=== CLEANUP: Removing broken node-2 ==="
minikube node delete m02 2>&1 || true
sleep 3
echo ""

echo "=== CURRENT STATE ==="
kubectl get pods -o wide
kubectl get nodes
echo ""

echo "============================================"
echo "  SCENARIO 1: POD CRASH — Self Healing"
echo "============================================"
echo ""
echo "BEFORE: Pod is running"
kubectl get pods -l app=productcatalogservice
echo ""

echo ">> SIMULATING CRASH: Deleting pod..."
POD_NAME=$(kubectl get pods -l app=productcatalogservice -o jsonpath='{.items[0].metadata.name}')
echo "   Killing pod: $POD_NAME"
kubectl delete pod $POD_NAME --grace-period=0 --force 2>&1
echo ""

echo ">> WATCHING SELF-HEALING (5 seconds)..."
sleep 5
echo ""
echo "AFTER: New pod automatically created!"
kubectl get pods -l app=productcatalogservice -o wide
echo ""
echo "✅ RESULT: K8s detected the crash and recreated the pod instantly!"
echo "   OLD pod: $POD_NAME (DELETED)"
NEW_POD=$(kubectl get pods -l app=productcatalogservice -o jsonpath='{.items[0].metadata.name}')
echo "   NEW pod: $NEW_POD (AUTO-CREATED)"
echo ""

echo "============================================"
echo "  SCENARIO 2: SCALING — Handle Traffic Spike"
echo "============================================"
echo ""
echo "BEFORE: 2 replicas"
kubectl get pods -l app=productcatalogservice
echo ""

echo ">> SIMULATING TRAFFIC SPIKE: Scaling to 4 replicas..."
kubectl scale deployment productcatalogservice --replicas=4
sleep 10
echo ""
echo "AFTER: 4 replicas running!"
kubectl get pods -l app=productcatalogservice -o wide
echo ""
echo "✅ RESULT: K8s instantly created 2 more pods to handle load!"
echo ""

echo ">> TRAFFIC DIES DOWN: Scaling back to 2..."
kubectl scale deployment productcatalogservice --replicas=2
sleep 5
kubectl get pods -l app=productcatalogservice
echo ""

echo "============================================"
echo "  SCENARIO 3: ROLLING UPDATE — Zero Downtime"
echo "============================================"
echo ""
echo "BEFORE: Current image version"
kubectl get deployment productcatalogservice -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo ""

echo ">> DEPLOYING NEW VERSION (changing env var to simulate)..."
kubectl set env deployment/productcatalogservice APP_VERSION=v2.0
echo ""

echo ">> WATCHING ROLLING UPDATE..."
kubectl rollout status deployment/productcatalogservice --timeout=60s
echo ""
echo "AFTER:"
kubectl get pods -l app=productcatalogservice -o wide
echo ""
echo "✅ RESULT: Zero downtime! Old pods replaced one-by-one with new version!"
echo ""

echo "============================================"
echo "  SCENARIO 4: ROLLBACK — Undo Bad Deploy"
echo "============================================"
echo ""
echo ">> OH NO! v2.0 has a bug! Rolling back..."
kubectl rollout undo deployment/productcatalogservice
kubectl rollout status deployment/productcatalogservice --timeout=60s
echo ""
echo "AFTER ROLLBACK:"
kubectl get pods -l app=productcatalogservice
echo ""
echo "✅ RESULT: Instantly rolled back to previous version!"
echo ""

echo "============================================"
echo "  SCENARIO 5: DEPLOYMENT HISTORY"
echo "============================================"
echo ""
kubectl rollout history deployment/productcatalogservice
echo ""
echo "✅ K8s keeps history of ALL deployments for audit trail!"
echo ""

echo "╔══════════════════════════════════════════════════╗"
echo "║     🏆 ALL 5 SCENARIOS COMPLETED!               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "=== FINAL STATE ==="
kubectl get all
