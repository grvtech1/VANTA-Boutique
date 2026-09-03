#!/usr/bin/env bash
# Promote an image SHA that is already running in staging to prod — as a Git commit.
# ArgoCD prod is manual-sync, so this only makes prod OutOfSync; a human approves the sync.
#
#   scripts/promote.sh <git-sha>            # pins prod to <git-sha> and commits
#   scripts/promote.sh --from-staging       # copies whatever staging currently pins
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

staging=kustomize/overlays/staging/kustomization.yaml
prod=kustomize/overlays/prod/kustomization.yaml

if [ "${1:-}" = "--from-staging" ]; then
  sha=$(grep -A2 'newName: docker.io/grvp1/frontend' "$staging" | awk '/newTag:/ {print $2}')
else
  sha="${1:?git sha (or --from-staging)}"
fi
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "not a git sha: $sha" >&2; exit 1; }

scripts/bump-image-tags.sh "$prod" "$sha"
git add "$prod"
git commit -m "release(prod): promote ${sha:0:7} to prod" -m "Manual ArgoCD sync required: argocd app sync vanta-boutique-prod"
echo
echo "Committed. Next:  git push   →  argocd app sync vanta-boutique-prod   (or approve in the UI)"
echo "Rollback later:   git revert HEAD && git push   →  sync again"
