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
[ ${#services[@]} -eq 0 ] && services=(frontend productcatalogservice reviewsservice)

[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }

for svc in "${services[@]}"; do
  # Within the image block whose newName is docker.io/grvp1/<svc>, replace the newTag line.
  sed -i -E "/^[[:space:]]*newName:[[:space:]]*docker\.io\/grvp1\/${svc}[[:space:]]*$/,/newTag:/ s|(newTag:[[:space:]]*).*|\1${tag}|" "$file"
  grep -qE "newName:[[:space:]]*docker\.io/grvp1/${svc}" "$file" || echo "warn: ${svc} block not found in ${file}" >&2
done

echo "== ${file} =="
grep -nE "newName:|newTag:" "$file"
