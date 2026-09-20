#!/usr/bin/env bash
# Promote an image SHA that is already running in staging to prod, as a Git commit.
# Prod pins both the tag (git SHA) and the digest, so prod runs the exact bytes staging ran.
# ArgoCD prod is manual-sync: this only makes prod OutOfSync; a human approves the sync.
#
#   scripts/promote.sh --from-staging       # copy staging's tag + digest for every service (preferred)
#   scripts/promote.sh <git-sha>            # pin prod to <git-sha>, resolving digests from Docker Hub
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

staging=kustomize/overlays/staging/kustomization.yaml
prod=kustomize/overlays/prod/kustomization.yaml

if [ "${1:-}" = "--from-staging" ]; then
  sha=$(awk '
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*docker\.io\/grvp1\/frontend[[:space:]]*$/ { hit=1; next }
    hit && /^[[:space:]]*newTag:/ { print $2; exit }
  ' "$staging")
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "staging is not pinned to a git sha (got '${sha}')" >&2; exit 1; }
  scripts/bump-image-tags.sh "$prod" "$sha" --copy-from "$staging"
else
  sha="${1:?git sha (or --from-staging)}"
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "not a git sha: $sha" >&2; exit 1; }
  scripts/bump-image-tags.sh "$prod" "$sha" --resolve
fi

git add "$prod"
git commit -m "release(prod): promote ${sha:0:7} to prod" \
           -m "Tags and digests pinned. Manual ArgoCD sync required: argocd app sync vanta-boutique-prod"
echo
echo "Committed. Next:  git push   →  argocd app sync vanta-boutique-prod   (or approve in the UI)"
echo "Rollback later:   git revert HEAD && git push   →  sync again"
