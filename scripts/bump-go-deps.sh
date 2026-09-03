#!/usr/bin/env bash
# Bump Go modules across the services this repo builds, tidy, and verify they still build.
# Used by .github/workflows/deps-bump.yml when the Trivy gate flags a fixable CVE in a dependency.
#
#   MODULES="golang.org/x/crypto@v0.55.0 google.golang.org/grpc@v1.79.3" scripts/bump-go-deps.sh
#
# Entries are module@MIN-version: a service is bumped only if it already depends on the module
# at an older version — never downgrades, never adds a new dependency. Use module@latest to
# force the newest release. Minimum fixed versions keep the diff small and reproducible.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODULES="${MODULES:-golang.org/x/crypto@v0.55.0 google.golang.org/grpc@v1.79.3}"
SERVICES="${SERVICES:-frontend productcatalogservice reviewsservice}"
newest() { printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1; }

for svc in $SERVICES; do
  dir="src/$svc"; [ -f "$dir/go.mod" ] || continue
  echo "== $svc"
  pushd "$dir" >/dev/null
  for entry in $MODULES; do
    m="${entry%@*}"; want="${entry#*@}"; [ "$entry" = "$m" ] && want=latest
    cur=$(go list -m -f '{{.Version}}' "$m" 2>/dev/null || true)
    if [ -z "$cur" ]; then echo "   $m: not a dependency, skip"; continue; fi
    if [ "$want" != latest ] && [ "$(newest "$cur" "$want")" = "$cur" ]; then echo "   $m: $cur already >= $want"; continue; fi
    go get "${m}@${want}" >/dev/null
    echo "   $m: $cur -> $(go list -m -f '{{.Version}}' "$m")"
  done
  go mod tidy
  go build ./...
  # copylocks is disabled on purpose: the upstream demo passes generated protobuf messages by
  # value, and newer protobuf-go embeds a sync.Mutex in MessageState. Harmless here, noisy in vet.
  go vet -copylocks=false ./...
  popd >/dev/null
done

echo; echo "== changed files =="; git status --short -- 'src/*/go.mod' 'src/*/go.sum' || true
