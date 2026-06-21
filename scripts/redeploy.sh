#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd ~/online-boutique

echo "=== RE-DEPLOYING PRODUCTCATALOG WITH FIXES ==="
kubectl apply -f kubernetes-manifests/productcatalogservice.yaml
echo ""

echo "=== WAITING FOR POD TO START (15s) ==="
sleep 15

echo "=== POD STATUS ==="
kubectl get pods
echo ""

echo "=== ROLLOUT STATUS ==="
kubectl rollout status deployment/productcatalogservice --timeout=60s 2>&1
echo ""

echo "=== DESCRIBE PODS (events) ==="
kubectl describe pod -l app=productcatalogservice 2>&1 | tail -25
