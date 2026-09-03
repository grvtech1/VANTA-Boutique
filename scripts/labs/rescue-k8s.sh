#!/bin/bash
export KUBECONFIG=/home/ubuntu/.kube/config

echo "=== Starting Kubelet ==="
sudo systemctl start kubelet

echo "=== Waiting for API Server to respond ==="
for i in {1..30}; do
  if kubectl get nodes &>/dev/null; then
    echo "✅ API server is responsive!"
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

echo "=== Scaling Down Monitoring Workloads (Prometheus/Grafana) ==="
kubectl scale deployment -n monitoring --all --replicas=0 --timeout=10s || true
kubectl scale statefulset -n monitoring --all --replicas=0 --timeout=10s || true

echo "=== Scaling Down Non-Essential ArgoCD Components ==="
kubectl scale deployment argocd-dex-server -n argocd --replicas=0 || true
kubectl scale deployment argocd-notifications-controller -n argocd --replicas=0 || true

echo "=== System Status ==="
free -h
kubectl get pods -A
