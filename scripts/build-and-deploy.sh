#!/bin/bash
# Build inside Minikube's Docker and deploy
export PATH="$HOME/.local/bin:$PATH"
cd ~/online-boutique

echo "=== STEP 1: CONNECT TO MINIKUBE's DOCKER ==="
eval $(minikube docker-env)
echo "Docker host: $DOCKER_HOST"
echo ""

echo "=== STEP 2: BUILD IMAGE INSIDE MINIKUBE ==="
docker build -t productcatalogservice:latest src/productcatalogservice/ 2>&1
echo ""

echo "=== STEP 3: VERIFY IMAGE EXISTS ==="
docker images | grep productcatalog
echo ""

echo "=== STEP 4: DELETE OLD DEPLOYMENT ==="
kubectl delete deployment productcatalogservice --ignore-not-found
sleep 3
echo ""

echo "=== STEP 5: RE-DEPLOY ==="
kubectl apply -f kubernetes-manifests/productcatalogservice.yaml
echo ""

echo "=== STEP 6: WAITING 20s FOR POD ==="
sleep 20

echo "=== POD STATUS ==="
kubectl get pods -l app=productcatalogservice
echo ""

echo "=== ROLLOUT STATUS ==="
kubectl rollout status deployment/productcatalogservice --timeout=90s 2>&1
echo ""

echo "=== ALL PODS ==="
kubectl get pods
