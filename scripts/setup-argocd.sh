#!/usr/bin/env bash
# Install ArgoCD (pinned) and register the app-of-apps root. Run once per cluster.
#   KUBECONFIG=./kubeconfig-aws scripts/setup-argocd.sh
set -euo pipefail
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"

echo "== 1. namespace + install ArgoCD ${ARGOCD_VERSION} =="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo; echo "== 2. register app-of-apps root (argocd/root.yaml) =="
kubectl apply -f argocd/root.yaml

echo; echo "== 3. initial admin password (change it after first login) =="
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo
echo "UI:   kubectl -n argocd port-forward svc/argocd-server 8443:443   → https://localhost:8443 (user: admin)"
echo "Apps: kubectl -n argocd get applications      (staging auto-syncs; prod waits for a manual sync)"
