#!/usr/bin/env bash
# Rewrite the `newTag:` of this repo's own images inside a kustomization.yaml.
# Used by the CD pipeline (staging) and scripts/promote.sh (prod).
#
#   scripts/bump-image-tags.sh kustomize/overlays/staging/kustomization.yaml <git-sha> [service ...]
set -euo pipefail

file="${1:?kustomization.yaml path}"
tag="${2:?image tag (git sha)}"
shift 2
services=("$@")
[ ${#services[@]} -eq 0 ] && services=(
  adservice cartservice checkoutservice currencyservice emailservice frontend inventoryservice
  loadgenerator paymentservice productcatalogservice recommendationservice reviewsservice
  shippingservice wishlistservice
)

[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }

for svc in "${services[@]}"; do
  # Within the image block for docker.io/grvp1/<svc> (matched on `name:` or `newName:`),
  # replace the newTag line.
  sed -i -E "/^[[:space:]]*-?[[:space:]]*(newName|name):[[:space:]]*docker\.io\/grvp1\/${svc}[[:space:]]*$/,/newTag:/ s|(newTag:[[:space:]]*).*|\1${tag}|" "$file"
  grep -qE "(newName|name):[[:space:]]*docker\.io/grvp1/${svc}[[:space:]]*$" "$file" || echo "warn: ${svc} block not found in ${file}" >&2
done

echo "== ${file} =="
grep -nE "name:|newTag:" "$file"
