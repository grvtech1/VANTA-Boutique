#!/bin/bash
# =============================================================================
# Multi-Node Setup + Failover Lab
# =============================================================================
export PATH="$HOME/.local/bin:$PATH"

echo "============================================"
echo "  MULTI-NODE FAILOVER LAB"
echo "============================================"
echo ""

# Step 1: Clean up old pods from previous exercises
echo "=== STEP 1: CLEANUP OLD PODS ==="
kubectl delete deployment cartservice --ignore-not-found 2>&1
kubectl delete deployment ride-api-deployment --ignore-not-found 2>&1
kubectl delete deployment web-deployment --ignore-not-found 2>&1
kubectl delete pod web-pod --ignore-not-found 2>&1
kubectl delete service cartservice redis-cart ride-api-service --ignore-not-found 2>&1
kubectl delete serviceaccount cartservice --ignore-not-found 2>&1
kubectl delete deployment redis-cart --ignore-not-found 2>&1
sleep 3
echo "Old pods cleaned up!"
echo ""

# Step 2: Add a second node to Minikube
echo "=== STEP 2: ADDING SECOND NODE ==="
echo "Running: minikube node add"
minikube node add 2>&1
echo ""

# Step 3: Check nodes
echo "=== STEP 3: CLUSTER NODES ==="
kubectl get nodes -o wide
echo ""

# Step 4: Scale to 2 replicas across nodes
echo "=== STEP 4: SCALING TO 2 REPLICAS ==="
kubectl scale deployment productcatalogservice --replicas=2
sleep 10
echo ""

echo "=== POD DISTRIBUTION ACROSS NODES ==="
kubectl get pods -o wide -l app=productcatalogservice
echo ""

echo "=== ALL PODS ==="
kubectl get pods -o wide
echo ""

echo "=== NODES ==="
kubectl get nodes
