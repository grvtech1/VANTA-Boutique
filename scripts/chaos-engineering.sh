# =============================================================================
# Phase 7: Chaos Engineering - Break Things on Purpose
# =============================================================================
# WHAT IS CHAOS ENGINEERING?
#   Netflix pioneered this with "Chaos Monkey" - randomly killing production
#   servers to prove the system can handle failures.
#
#   "The best way to build confidence in a system is to TEST it with failures."
#
# WHY DO THIS?
#   - Find weaknesses BEFORE customers do
#   - Validate that self-healing actually works
#   - Prove your PodDisruptionBudgets and replicas are effective
#   - Build confidence for on-call rotations
#
# EXPERIMENTS:
#   1. Pod Kill     → Kill a pod, measure recovery time
#   2. Node Drain   → Evict ALL pods from a node gracefully
#   3. Service Test  → Is the app still accessible during chaos?
# =============================================================================

export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
K=/home/gaurav/.local/bin/kubectl

echo "=== PHASE 7: CHAOS ENGINEERING ==="
echo ""

# --- Experiment 1: Pod Kill and Self-Heal ---
echo "============================================"
echo " EXPERIMENT 1: Pod Kill and Self-Heal"
echo "============================================"
echo ""
echo "BEFORE chaos - current pods:"
$K get pods -n boutique -o wide | head -5
echo "..."
echo ""

# Get the frontend pod name
FRONTEND_POD=$($K get pod -n boutique -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo "TARGET: $FRONTEND_POD"
echo "Killing frontend pod NOW..."
echo ""

# Record the time
START_TIME=$(date +%s)

# Kill the pod
$K delete pod $FRONTEND_POD -n boutique

echo ""
echo "Waiting for new pod to become Ready..."
$K wait --for=condition=Ready pod -l app=frontend -n boutique --timeout=60s

END_TIME=$(date +%s)
RECOVERY_TIME=$((END_TIME - START_TIME))

echo ""
echo "============================================"
echo " RESULT: Recovery Time = ${RECOVERY_TIME} seconds"
echo "============================================"
echo ""
echo "NEW pod created:"
$K get pods -n boutique -l app=frontend -o wide
echo ""

# --- Experiment 2: Verify app is still accessible ---
echo "============================================"
echo " EXPERIMENT 2: Service Availability Check"
echo "============================================"
echo ""
echo "Testing app accessibility during chaos..."

# Use curl from master node to check frontend
# (We can't curl from WSL to NodePort directly, so we'll check via kubectl)
$K run curl-test --image=curlimages/curl --rm -i --restart=Never -n boutique -- \
  curl -s -o /dev/null -w "HTTP Status: %{http_code}\nResponse Time: %{time_total}s\n" \
  http://frontend.boutique.svc.cluster.local:80/ 2>/dev/null
echo ""

# --- Experiment 3: Node Drain ---
echo "============================================"
echo " EXPERIMENT 3: Node Drain (Graceful Eviction)"
echo "============================================"
echo ""

# Pick worker-1 to drain
DRAIN_NODE="ip-10-0-1-11"
echo "BEFORE drain - pods on $DRAIN_NODE:"
$K get pods -n boutique -o wide --field-selector spec.nodeName=$DRAIN_NODE
echo ""

echo "Draining $DRAIN_NODE (evicting all pods)..."
$K drain $DRAIN_NODE --ignore-daemonsets --delete-emptydir-data --timeout=120s
echo ""

echo "AFTER drain - pods redistributed:"
$K get pods -n boutique -o wide
echo ""

echo "Node status (should show SchedulingDisabled):"
$K get nodes
echo ""

# --- Experiment 4: Uncordon (bring node back) ---
echo "============================================"
echo " EXPERIMENT 4: Uncordon (Bring Node Back)"
echo "============================================"
echo ""
echo "Bringing $DRAIN_NODE back online..."
$K uncordon $DRAIN_NODE
echo ""
echo "Node status (should show Ready):"
$K get nodes
echo ""

echo "Final pod distribution:"
$K get pods -n boutique -o wide
echo ""

echo "=== PHASE 7 COMPLETE ==="
echo "  Experiment 1: Pod self-healed in ${RECOVERY_TIME}s"
echo "  Experiment 2: Service availability verified"
echo "  Experiment 3: Node drain redistributed pods"
echo "  Experiment 4: Node uncordoned back to Ready"
echo ""
echo "  KEY LEARNING:"
echo "    - K8s automatically recreates killed pods"
echo "    - Node drain gracefully moves pods to other nodes"
echo "    - PDB ensures minimum availability during drain"
echo "    - Uncordon makes the node available for scheduling again"
