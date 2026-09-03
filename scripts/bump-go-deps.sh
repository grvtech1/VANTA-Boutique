#!/usr/bin/env bash
# Bump Go modules to their latest release across the services this repo builds, tidy, and
# verify they still build/vet. Used by .github/workflows/deps-bump.yml when the Trivy gate
# flags a fixable CRITICAL in a dependency; also runnable locally with a Go toolchain.
#
#   MODULES="golang.org/x/crypto google.golang.org/grpc" scripts/bump-go-deps.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODULES="${MODULES:-golang.org/x/crypto google.golang.org/grpc}"
SERVICES="${SERVICES:-frontend productcatalogservice reviewsservice}"

for svc in $SERVICES; do
  dir="src/$svc"; [ -f "$dir/go.mod" ] || continue
  echo "== $svc"
  pushd "$dir" >/dev/null
  for m in $MODULES; do
    # only bump modules already in this service's graph — never add new dependencies
    if go list -m all 2>/dev/null | grep -q "^${m} "; then
      before=$(go list -m "$m" | awk '{print $2}')
      go get "${m}@latest" >/dev/null
      after=$(go list -m "$m" | awk '{print $2}')
      echo "   $m: $before -> $after"
    fi
  done
  go mod tidy
  go build ./... && go vet ./...
  popd >/dev/null
done

echo; echo "== changed files =="; git status --short -- 'src/*/go.mod' 'src/*/go.sum' || true
