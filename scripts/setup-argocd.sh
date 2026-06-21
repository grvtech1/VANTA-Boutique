#!/bin/bash
# ============================================================
# Phase 12: ArgoCD — Two-step approach
# Step 1: Download manifest on master node itself (fast)
# Step 2: Apply locally from master (no internet timeout)
# ============================================================
set -e
export PATH=$HOME/.local/bin:$PATH
export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws

MASTER_IP="3.111.11.116"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     Phase 12: ArgoCD GitOps — Fast Install      ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── STEP 1: Check if argocd namespace already exists ────────
echo -e "${YELLOW}=== STEP 1: Namespace Check ===${NC}"
kubectl get namespace argocd 2>/dev/null && echo "  argocd namespace exists" || \
  kubectl create namespace argocd
echo ""

# ── STEP 2: Download ArgoCD manifest ON the master node ─────
echo -e "${YELLOW}=== STEP 2: Downloading ArgoCD manifest on master node ===${NC}"
echo "  (Downloading directly on EC2 — much faster than via WSL)"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
  'curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -o /tmp/argocd-install.yaml && echo "Downloaded: $(wc -l < /tmp/argocd-install.yaml) lines"'
echo -e "${GREEN}  ✅ Manifest downloaded on master${NC}"
echo ""

# ── STEP 3: Apply from master node directly ──────────────────
echo -e "${YELLOW}=== STEP 3: Applying ArgoCD manifests ===${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
  'kubectl apply --server-side -n argocd -f /tmp/argocd-install.yaml 2>&1 | tail -20'
echo -e "${GREEN}  ✅ ArgoCD manifests applied${NC}"
echo ""

# ── STEP 4: Pin ArgoCD pods to master node ──────────────────
echo -e "${YELLOW}=== STEP 4: Pinning ArgoCD to master (it has more RAM) ===${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP << 'SSHEOF'
for deploy in argocd-server argocd-repo-server argocd-redis argocd-dex-server argocd-notifications-controller argocd-applicationset-controller; do
  kubectl patch deployment $deploy -n argocd \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"k8s-master"}},{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}]' 2>/dev/null && echo "  Pinned: $deploy" || echo "  Skipped: $deploy (not a deployment)"
done
kubectl patch statefulset argocd-application-controller -n argocd \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"k8s-master"}},{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}]' 2>/dev/null && echo "  Pinned: argocd-application-controller" || true
SSHEOF
echo -e "${GREEN}  ✅ Pods pinned to k8s-master${NC}"
echo ""

# ── STEP 5: Expose ArgoCD as NodePort ───────────────────────
echo -e "${YELLOW}=== STEP 5: Exposing ArgoCD UI on NodePort 31443 ===${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
  "kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"NodePort\"}}' 2>/dev/null && echo 'NodePort set' || echo 'Service not ready yet'"
echo ""

# ── STEP 6: Wait for pods ────────────────────────────────────
echo -e "${YELLOW}=== STEP 6: Waiting for pods to start (90 seconds) ===${NC}"
sleep 30
echo "  30s passed..."
sleep 30
echo "  60s passed..."
sleep 30
echo "  90s passed. Checking status..."
echo ""

# ── STEP 7: Show status ──────────────────────────────────────
echo -e "${YELLOW}=== STEP 7: Pod Status ===${NC}"
kubectl get pods -n argocd -o wide
echo ""

# ── STEP 8: Patch NodePort to fixed port 31443 ───────────────
echo -e "${YELLOW}=== STEP 8: Setting NodePort to 31443 ===${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
  "kubectl get svc argocd-server -n argocd -o yaml | grep nodePort || echo 'Getting current NodePort...'"
kubectl patch svc argocd-server -n argocd \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":31443}]' 2>/dev/null || true
echo ""

# ── STEP 9: Get admin password ───────────────────────────────
echo -e "${YELLOW}=== STEP 9: ArgoCD Admin Password ===${NC}"
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null) || PASS=""

if [ -n "$PASS" ]; then
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════╗"
  echo "║         ✅ ArgoCD Ready!                        ║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║  UI URL:   http://3.111.11.116:31443            ║"
  echo "║  Username: admin                                ║"
  echo "║  Password: $PASS"
  echo -e "╚══════════════════════════════════════════════════╝${NC}"
else
  echo -e "${YELLOW}  Password not ready — run this after pods start:${NC}"
  echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi
