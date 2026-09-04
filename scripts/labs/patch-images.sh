#!/bin/bash
export PATH=/home/gaurav/.local/bin:/usr/bin:/bin:$PATH
export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
VERSION="${VERSION:-latest}"   # git SHA from kustomize/overlays/staging in real runs
BASE="docker.io/grvp1"

echo "=== Updating images to docker.io/grvp1 (this repo's CI-built images) ==="

declare -A IMAGES
IMAGES[adservice]="adservice"
IMAGES[cartservice]="cartservice"
IMAGES[checkoutservice]="checkoutservice"
IMAGES[currencyservice]="currencyservice"
IMAGES[emailservice]="emailservice"
IMAGES[frontend]="frontend"
IMAGES[paymentservice]="paymentservice"
IMAGES[productcatalogservice]="productcatalogservice"
IMAGES[recommendationservice]="recommendationservice"
IMAGES[shippingservice]="shippingservice"

for deploy in "${!IMAGES[@]}"; do
  IMAGE="${BASE}/${IMAGES[$deploy]}:${VERSION}"
  echo "  Updating $deploy → $IMAGE"
  kubectl set image deployment/$deploy \
    server=$IMAGE \
    client=$IMAGE \
    $deploy=$IMAGE \
    -n boutique 2>/dev/null || true
  kubectl patch deployment $deploy -n boutique \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"},{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"'"$IMAGE"'"}]' \
    2>/dev/null || true
done

echo ""
echo "=== Waiting 60s for pods to start pulling images ==="
sleep 60
echo ""
echo "=== POD STATUS ==="
kubectl get pods -n boutique -o wide 2>&1
