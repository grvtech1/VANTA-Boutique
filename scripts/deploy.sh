#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd ~/online-boutique

echo "=== DEPLOYING PRODUCTCATALOG TO KUBERNETES ==="
kubectl apply -f kubernetes-manifests/productcatalogservice.yaml
echo ""

echo "=== DEPLOYING CART + REDIS ==="
kubectl apply -f kubernetes-manifests/cartservice.yaml
echo ""

echo "=== WAITING FOR PODS TO START (10s) ==="
sleep 10

echo "=== POD STATUS ==="
kubectl get pods -o wide
echo ""

echo "=== SERVICES ==="
kubectl get svc
echo ""

echo "=== DEPLOYMENT STATUS ==="
kubectl rollout status deployment/productcatalogservice --timeout=60s 2>&1 || true
kubectl rollout status deployment/redis-cart --timeout=60s 2>&1 || true
