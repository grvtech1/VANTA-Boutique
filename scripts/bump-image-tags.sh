#!/usr/bin/env bash
# Pin this repo's images inside a kustomization.yaml: the `newTag:` (git SHA, for humans)
# and the `digest:` (sha256 of the manifest, what the runtime actually pulls).
# Kustomize renders both as  image: docker.io/grvp1/<svc>:<sha>@sha256:...  — the tag is
# informational, the digest is what Kubernetes resolves, so a re-pushed tag can never
# change what runs.
#
#   scripts/bump-image-tags.sh <kustomization.yaml> <git-sha> --resolve            [svc ...]
#       look each digest up on Docker Hub over HTTPS (no docker daemon needed) — used by CD
#   scripts/bump-image-tags.sh <kustomization.yaml> <git-sha> --copy-from <other.yaml> [svc ...]
#       copy tag + digest from another overlay (prod takes exactly what staging runs)
#   scripts/bump-image-tags.sh <kustomization.yaml> <git-sha>                       [svc ...]
#       tag only (dev/local loops)
set -euo pipefail

file="${1:?kustomization.yaml path}"
tag="${2:?image tag (git sha)}"
shift 2

mode="tag"
from=""
if [ "${1:-}" = "--resolve" ]; then mode="resolve"; shift
elif [ "${1:-}" = "--copy-from" ]; then mode="copy"; from="${2:?source kustomization.yaml}"; shift 2
fi

services=("$@")
[ ${#services[@]} -eq 0 ] && services=(
  adservice cartservice checkoutservice currencyservice emailservice frontend inventoryservice
  loadgenerator paymentservice recommendationservice reviewsservice productcatalogservice
  shippingservice wishlistservice
)

[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }
[ "$mode" = "copy" ] && [ ! -f "$from" ] && { echo "no such file: $from" >&2; exit 1; }

registry="registry-1.docker.io"
auth="https://auth.docker.io/token?service=registry.docker.io"
accept="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

# resolve_digest <repo> <tag>  ->  sha256:...   (anonymous pull token; HEAD on the manifest)
resolve_digest() {
  local repo="$1" ref="$2" token digest
  token=$(curl -fsS "${auth}&scope=repository:${repo}:pull" | sed -E 's/.*"token":"([^"]+)".*/\1/')
  digest=$(curl -fsSI -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
             "https://${registry}/v2/${repo}/manifests/${ref}" \
           | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}')
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "could not resolve digest for ${repo}:${ref}" >&2; return 1; }
  printf '%s' "$digest"
}

# digest_from_file <kustomization.yaml> <svc>  ->  sha256:...  (empty if the block has none)
digest_from_file() {
  awk -v want="docker.io/grvp1/$2" '
    /^[[:space:]]*-[[:space:]]*(newName|name):/ { cur=$NF }
    cur==want && /^[[:space:]]*digest:/         { print $2; exit }
  ' "$1"
}

for svc in "${services[@]}"; do
  digest=""
  case "$mode" in
    resolve) digest=$(resolve_digest "grvp1/${svc}" "$tag") ;;
    copy)    digest=$(digest_from_file "$from" "$svc")
             [ -n "$digest" ] || { echo "no digest for ${svc} in ${from} — resolve it there first" >&2; exit 1; } ;;
  esac

  # Rewrite the block for docker.io/grvp1/<svc>: set newTag, then set or insert digest
  # (or drop it in tag-only mode so a stale digest never survives a tag change).
  tmp=$(mktemp)
  awk -v want="docker.io/grvp1/${svc}" -v tag="$tag" -v digest="$digest" '
    function flush() {
      if (inblock && digest != "" && !seen) print indent "digest: " digest
      inblock = 0; seen = 0
    }
    /^[[:space:]]*-[[:space:]]*(newName|name):/ { flush(); inblock = ($NF == want); next_print = 1 }
    /^[^[:space:]]/ && !/^images:/                { flush() }
    inblock && /^[[:space:]]*newTag:/ {
      match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
      print indent "newTag: " tag; next
    }
    inblock && /^[[:space:]]*digest:/ {
      if (digest == "") next
      match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
      print indent "digest: " digest; seen = 1; next
    }
    { print }
    END { flush() }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  grep -qE "(newName|name):[[:space:]]*docker\.io/grvp1/${svc}[[:space:]]*$" "$file" \
    || echo "warn: ${svc} block not found in ${file}" >&2
done

echo "== ${file} =="
grep -nE "name:|newTag:|digest:" "$file"
