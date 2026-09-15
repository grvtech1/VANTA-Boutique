# MySQL reviews verification - 2026-09-11

Scope: local working-tree changes based on `a8218646`. No commit, GitHub push,
Docker Hub publication, cloud deployment or existing PostgreSQL data transfer
was performed. The unrelated `terraform/etcd-snap.db` file was not changed.

## Results

| Check | Result |
| --- | --- |
| Go 1.26.2 module tidy, formatting, vet and ordinary unit tests | Passed |
| Full reviews-service tests against MySQL 8.4.11 with `-race -count=1` | 13 top-level tests passed; integration tests enabled, not skipped |
| Unicode and quoted comment round-trip | Passed |
| Case-sensitive and trailing-space-sensitive product lookup | Passed |
| Two database pools and 20 concurrent writes | Passed; all 20 reviews returned |
| Query return limit, newest-first ordering and aggregate rating | Passed |
| Database rating constraint, cancelled query and invalid DSN | Passed |
| Generated gRPC client/server with actual MySQL persistence | Passed |
| Kustomize root, 5 overlays and 2 test overlays | Passed rendering |
| Helm lint, default render and two-replica MySQL render | Passed |
| Helm rejection of two in-memory replicas | Passed |
| Existing production Dockerfile build | Passed; local tag `vanta-reviews-mysql:local-check` |
| Official MySQL image with UID/GID 999, all capabilities dropped | Started successfully; authenticated SQL query passed |
| Built distroless service with read-only filesystem and dropped capabilities | Started; gRPC reflection and review APIs responded |
| Application container restart | Same synthetic review ID remained readable |
| MySQL container restart on its test volume | Same synthetic review ID remained readable |
| MySQL stopped, then recovered | Health became NOT_SERVING, then SERVING without restarting the app |
| Git whitespace check | Passed |

The synthetic smoke review was `9c6e6c37-36b6-4b9c-bd85-1a89affbf3fa`, product
`MYSQL_MIGRATION_SMOKE_20260911`, count 1, average rating 5. This is disposable
test data, not a merchant or customer record.

## Reproduce the automated checks

From the repository root:

```sh
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml up --abort-on-container-exit --exit-code-from tests
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml down -v
docker build -t vanta-reviews-mysql:local-check src/reviewsservice
helm lint helm-chart
helm template vanta helm-chart --set reviewsService.database.enabled=true --set reviewsService.replicas=2
kubectl kustomize kustomize/overlays/staging
kubectl kustomize kustomize/overlays/prod
```

The two temporary database containers and the smoke application were isolated
from existing Kubernetes workloads, with no published host ports. Go/Docker
dependency downloads were required; one initial Go proxy transfer failed and
the retry succeeded. The existing Docker Desktop engine was started for testing.

## Still required before external deployment

- Publish/review the code and build a matching immutable image through CI.
- Coordinate image/configuration cutover; existing overlay tags still reference
  older images. Do not let automatic GitOps sync apply this configuration first.
- Follow `REVIEWS_MYSQL_MIGRATION.md` for backup, data transfer and rollback.
- Validate actual Kubernetes scheduling, storage provisioning and NetworkPolicy
  enforcement. Rendering and a non-root Docker test are not live-cluster proof.
- Verify production credentials, TLS, database HA, offsite backup/restore and sizing.
- Run the full public CI/security scanning pipeline. Only the changed reviews
  service and deployment rendering were exercised here, not all application images.

Resume wording and the public repository were deliberately left unchanged until
the new implementation is reviewed and published consistently.
