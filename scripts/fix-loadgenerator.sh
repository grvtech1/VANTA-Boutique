#!/bin/bash
export PATH=/home/gaurav/.local/bin:/usr/bin:/bin:$PATH
export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
VERSION="v0.10.1"
BASE="gcr.io/google-samples/microservices-demo"

echo "=== Fix loadgenerator ==="
kubectl set image deployment/loadgenerator \
  loadgenerator=${BASE}/loadgenerator:${VERSION} \
  -n boutique 2>&1

# Also patch imagePullPolicy via file
kubectl get deployment loadgenerator -n boutique -o yaml | \
  sed 's/imagePullPolicy: Never/imagePullPolicy: Always/g' | \
  sed "s|image: loadgenerator|image: ${BASE}/loadgenerator:${VERSION}|g" | \
  kubectl apply -f - 2>&1

echo ""
echo "=== Delete old stuck adservice pod ==="
kubectl delete pod -n boutique -l app=adservice --field-selector=status.phase!=Running --force 2>&1 || true

echo ""
echo "=== Waiting 45s for pods ==="
sleep 45

echo ""
echo "=== FINAL POD STATUS ==="
kubectl get pods -n boutique -o wide 2>&1

echo ""
echo "=== FRONTEND ACCESS URL ==="
WORKER_IP="13.207.61.122"
NODE_PORT=$(kubectl get svc frontend-external -n boutique -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
echo "Open in browser: http://${WORKER_IP}:${NODE_PORT}"
echo "Or: http://13.127.4.237:${NODE_PORT}"
