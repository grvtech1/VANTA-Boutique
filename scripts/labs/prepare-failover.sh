#!/bin/bash
# =============================================================================
# Wait for Node-2 + Copy Image + Start Failover Tests
# =============================================================================
export PATH="$HOME/.local/bin:$PATH"

echo "=== WAITING FOR NODE-2 TO BE READY ==="
for i in $(seq 1 30); do
  STATUS=$(kubectl get node minikube-m02 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$STATUS" = "True" ]; then
    echo "Node minikube-m02 is READY!"
    break
  fi
  echo "  Waiting... ($i/30) Status: $STATUS"
  sleep 5
done
echo ""

echo "=== CLUSTER NODES ==="
kubectl get nodes -o wide
echo ""

echo "=== COPYING IMAGE TO NODE-2 ==="
# Save image from node-1 and load into node-2
eval $(minikube docker-env)
docker save productcatalogservice:latest | docker --host $(minikube docker-env -p minikube --node minikube-m02 --shell bash 2>/dev/null | grep DOCKER_HOST | cut -d'"' -f2) load 2>&1 || {
  echo "Direct copy failed, using minikube image load..."
  docker save productcatalogservice:latest -o /tmp/pcs-image.tar
  minikube image load /tmp/pcs-image.tar --node minikube-m02 2>&1 || {
    echo "Using alternative: minikube cp + docker load..."
    minikube cp /tmp/pcs-image.tar minikube-m02:/tmp/pcs-image.tar 2>&1
    minikube ssh -n minikube-m02 "docker load < /tmp/pcs-image.tar" 2>&1
  }
  rm -f /tmp/pcs-image.tar
}
echo ""

echo "=== DELETE PODS TO RESCHEDULE ACROSS NODES ==="
kubectl delete pods -l app=productcatalogservice
sleep 15
echo ""

echo "=== POD DISTRIBUTION (should be on different nodes!) ==="
kubectl get pods -o wide -l app=productcatalogservice
echo ""

echo "=== ALL RESOURCES ==="
kubectl get pods -o wide
echo ""
kubectl get nodes
