# =============================================================================
# Phase 4: Install Metrics Server + Configure HPA
# =============================================================================
# WHY METRICS-SERVER?
#   HPA needs real-time CPU/memory data to decide when to scale.
#   metrics-server collects this from kubelet on every node.
#   Without it: kubectl top nodes/pods won't work, HPA can't function.
#
# WHY --kubelet-insecure-tls?
#   kubeadm generates self-signed certificates.
#   metrics-server refuses to connect unless we tell it to skip TLS verification.
#   In production (EKS/GKE), certificates are properly signed so this isn't needed.
# =============================================================================

export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
K=/home/gaurav/.local/bin/kubectl

echo "=== PHASE 4: HPA (Horizontal Pod Autoscaler) ==="
echo ""

# --- Step 1: Install metrics-server ---
echo "--- Step 1: Installing metrics-server ---"
$K apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
echo ""

# --- Step 2: Patch metrics-server for kubeadm self-signed certs ---
echo "--- Step 2: Patching metrics-server for kubeadm (--kubelet-insecure-tls) ---"
$K patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
echo ""

# --- Step 3: Wait for metrics-server to be ready ---
echo "--- Step 3: Waiting for metrics-server to be ready (up to 90s) ---"
$K rollout status deployment/metrics-server -n kube-system --timeout=90s
echo ""

# --- Step 4: Verify metrics-server works ---
echo "--- Step 4: Waiting 15s for metrics to populate, then checking ---"
sleep 15
echo "Node metrics:"
$K top nodes
echo ""
echo "Pod metrics (boutique):"
$K top pods -n boutique --sort-by=memory | head -15
echo ""

# --- Step 5: Create HPA for frontend ---
echo "--- Step 5: Creating HPA for frontend service ---"
cat <<'EOF' | $K apply -f -
# =============================================================================
# HPA (Horizontal Pod Autoscaler) for Frontend
# =============================================================================
# WHAT IT DOES:
#   Watches frontend's CPU usage every 15 seconds.
#   If CPU > 50% of requested → scale UP (add more pods)
#   If CPU < 50% for 5 min  → scale DOWN (remove pods)
#
# HOW THE MATH WORKS:
#   Frontend requests 100m CPU (0.1 vCPU)
#   Target: 50% = 50m
#   If actual usage = 80m → 80/50 = 1.6 → need 2 replicas
#   If actual usage = 150m → 150/50 = 3.0 → need 3 replicas
#   If actual usage = 30m → 30/50 = 0.6 → need 1 replica
#
# WHY max=3 NOT max=10:
#   Workers have only 913MB RAM each (94-99% used!)
#   Each frontend pod needs ~128Mi
#   We can fit maybe 2-3 extra pods max across the cluster
# =============================================================================
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: boutique
  labels:
    app: frontend
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Pods
        value: 2
        periodSeconds: 60
EOF
echo ""

# --- Step 6: Verify HPA ---
echo "--- Step 6: HPA Status ---"
sleep 5
$K get hpa -n boutique
echo ""

echo "=== PHASE 4 COMPLETE ==="
echo "  metrics-server: installed and patched for kubeadm"
echo "  HPA: frontend will auto-scale 1-3 replicas at 50% CPU"
echo "  loadgenerator is already running - watch HPA with:"
echo "    kubectl get hpa -n boutique -w"
