#!/usr/bin/env bash
# Force an ArgoCD refresh/sync of one Application (default: staging).
#   scripts/sync-app.sh vanta-boutique-prod   # after scripts/promote.sh + git push
set -euo pipefail
app="${1:-vanta-boutique-staging}"
if command -v argocd >/dev/null 2>&1; then
  argocd app sync "$app" --prune
else
  # No CLI: ask the controller to refresh; auto-sync apps reconcile, manual apps show OutOfSync.
  kubectl -n argocd annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite
  kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
fi
