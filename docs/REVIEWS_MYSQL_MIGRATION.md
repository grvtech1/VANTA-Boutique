# Reviews: PostgreSQL to MySQL

The reviews service and its deployment defaults moved from PostgreSQL to MySQL 8.4 so that the
platform runs one database engine. This change does not migrate an existing database, publish
an image, or touch a running cluster on its own. The gRPC API and the registry are unchanged.

## Compatibility boundary

- The service uses `database/sql` with `go-sql-driver/mysql`. `DATABASE_URL` is now a MySQL
  DSN, not a PostgreSQL connection URL.
- Without a DSN the single-replica in-memory mode still works.
- PostgreSQL's UUID type becomes an ASCII UUID string; existing IDs and Unix timestamps can be
  preserved by a separately reviewed data transfer.
- The MySQL table uses InnoDB and `utf8mb4_0900_bin`: product IDs stay case-sensitive and
  trailing-space-sensitive; comments support Unicode.
- The return limit is unchanged; MySQL does not delete older rows automatically.
- The API still validates ratings and field lengths, and the database enforces ratings 1 to 5.
  All queries use bound parameters.

## Fresh installation

Use the `reviews-persistence` Kustomize component with a MySQL-capable reviewsservice image. It
provisions `reviews-mysql` (Deployment, Service, Secret, PVC). The PVC is deliberately not named
`reviews-db`: MySQL must never mount a PostgreSQL data directory. The component ships
demonstration credentials and unencrypted in-cluster SQL; it is not a production database.

The Helm chart only injects a DSN when `reviewsService.database.enabled=true` and does not
provision a database. Its default Secret is `reviews-mysql`, key `database-url`. When using Helm
without the Kustomize component, provision MySQL and that Secret yourself.

Existing staging and prod overlays keep pointing at earlier image tags until CD promotes a new
build. Do not sync the new DSN and manifests against a PostgreSQL-only image: cut the image and
the database over together.

## Existing data: controlled cutover

1. Inventory the current context and namespace, the deployed image digest, Secret names,
   PostgreSQL version, row counts, PVC names and reclaim policies. Do not print credentials or
   commit database exports.
2. Pause automatic sync and pruning for the maintenance window. Protect the old `reviews-db`
   PVC before its manifest leaves Git; the new PVC's `Prune=false` annotation does not protect
   the old one.
3. Back up PostgreSQL and prove a restore into an isolated instance. Keep the old image and
   configuration. A MySQL server cannot restore a `pg_dump`, and a filesystem copy is not a
   cross-engine migration.
4. Provision MySQL on a new volume or a managed instance, with its own credentials, TLS,
   connection limits and backups.
5. Stop reviews writes and drain writers before the final export. Export the six reviews
   columns with a reviewed ETL step, preserving IDs, product IDs, authors, ratings, comments and
   timestamps. Do not convert dumps with string replacements.
6. Import into an empty MySQL target; reject duplicates and invalid rows instead of overwriting
   them. Compare total and per-product counts, row checksums, Unicode samples, aggregate ratings
   and boundary lengths.
7. Test the new image against MySQL: GetReviews, AddReview, persistence across restarts,
   two-replica visibility, readiness on DB failure, backup and restore. Promote the image and
   the matching DSN together, then resume traffic.
8. Watch errors, connection counts and readiness. Keep the old backup and PVC through the
   rollback window. Resume normal reconciliation after acceptance.

## Rollback boundary

Before MySQL has accepted writes: restore the previous image and its PostgreSQL Secret,
networking and retained database. Reverting only the image is not enough. After MySQL has
accepted writes, PostgreSQL is stale: stop writes and reconcile before switching back. There is
no lossless one-command rollback across database engines.

## Verification (2026-09-11)

Run on a local working tree at `a8218646` before the change was committed. Two throwaway
containers (MySQL 8.4.11 and the built service), no host ports, no cluster involved.

| Check | Result |
| --- | --- |
| Go 1.26 tidy, gofmt, vet, unit tests | pass |
| Full reviews test suite against MySQL 8.4.11 with `-race -count=1` | 13 top-level tests pass, integration tests enabled |
| Unicode and quoted comment round-trip | pass |
| Case-sensitive and trailing-space-sensitive product lookup | pass |
| Two DB pools, 20 concurrent writes | pass, all 20 rows returned |
| Return limit, newest-first ordering, aggregate rating | pass |
| Rating constraint, cancelled query, invalid DSN | pass |
| Generated gRPC client and server against real MySQL | pass |
| Kustomize root, 5 overlays, 2 test overlays | render |
| Helm lint, default render, two-replica MySQL render; two in-memory replicas rejected | pass |
| Dockerfile build; official MySQL image as UID/GID 999 with all capabilities dropped | start, authenticated query OK |
| Distroless service with read-only filesystem and dropped capabilities | start, reflection and review RPCs respond |
| App restart, then MySQL restart on its volume | the same review ID stays readable |
| MySQL stopped and recovered | health goes NOT_SERVING then SERVING without an app restart |

Reproduce from the repo root:

```sh
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml up --abort-on-container-exit --exit-code-from tests
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml down -v
docker build -t vanta-reviews-mysql:local-check src/reviewsservice
helm lint helm-chart
helm template vanta helm-chart --set reviewsService.database.enabled=true --set reviewsService.replicas=2
kubectl kustomize kustomize/overlays/staging
kubectl kustomize kustomize/overlays/prod
```

What this run does not prove: a live cluster deployment, transfer of existing data, production
TLS, off-site backup restoration, or scanning of the other 13 images. Those go through the normal
CI pipeline and the cutover steps above.
