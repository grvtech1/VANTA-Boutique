# Reviews: PostgreSQL to MySQL

This revision changes the reviews service implementation and deployment defaults
to MySQL 8.4. It does not migrate an existing database, publish an image, or change
a running cluster. The gRPC API and Docker Hub registry remain unchanged.

## Compatibility boundary

- The service uses `database/sql` and `go-sql-driver/mysql`. `DATABASE_URL` now
  contains a MySQL driver DSN, not the old PostgreSQL connection URL.
- Without a DSN, the existing single-replica in-memory mode remains available.
- PostgreSQL's UUID type becomes an ASCII UUID string; existing UUID values and
  Unix timestamps can be preserved during a separately reviewed data transfer.
- The MySQL table uses InnoDB and `utf8mb4_0900_bin`: product IDs remain
  case-sensitive and trailing-space-sensitive. Comments support Unicode.
- The existing return limit remains; MySQL does not delete older rows automatically.
- The API still validates ratings and field lengths. The database additionally
  enforces ratings between 1 and 5. All application queries use bound parameters.

## Fresh local installation

Use the `reviews-persistence` Kustomize component with a newly built MySQL-capable
reviewsservice image. It provisions `reviews-mysql` (Deployment, Service, Secret,
PVC). The PVC is deliberately NOT named `reviews-db`: MySQL must never mount a
PostgreSQL data directory. The component contains demonstration credentials and
unencrypted in-cluster SQL. It is not a production-ready HA database.

Helm only injects a DSN when `reviewsService.database.enabled=true`; it does not
provision a database. Its default existing Secret is now `reviews-mysql`, key
`database-url`. Provision a MySQL database and this Secret independently when
using Helm without the Kustomize component.

IMPORTANT: existing staging/prod image tags still refer to earlier builds until
CI/CD promotes a new image. Do not sync the changed DSN/manifests with an old
PostgreSQL-only image. Gate the image and database cutover together.

## Existing data: controlled cutover required

1. Inventory the current context/namespace, deployed image digest, Secret names,
   PostgreSQL version, row counts, PVC names and reclaim policies. Do not print
   credentials or commit database exports. This task has not inspected live data.
2. Pause automatic GitOps sync/pruning for the agreed maintenance window. Protect
   the OLD `reviews-db` PVC against pruning before removing its manifest from Git.
   The new PVC's `Prune=false` annotation does not protect the old PVC retroactively.
3. Back up PostgreSQL and prove restoration into an isolated PostgreSQL instance.
   Preserve the old image/configuration. A MySQL server cannot restore a `pg_dump`
   directly, and a filesystem backup alone is not a cross-engine migration.
4. Provision MySQL on a NEW volume or separate managed instance. Use separately
   managed credentials, verified TLS, appropriate connection capacity and backups.
5. Stop reviews writes and drain all existing writers before the final export.
   Export the six reviews columns with a structured, reviewed ETL process. Preserve
   review IDs, product IDs, authors, ratings, comments and Unix timestamps. Do not
   convert SQL dumps with string replacements. There is no automatic ETL in this change.
6. Import into an empty MySQL target and reject duplicates or invalid rows rather
   than silently overwriting/truncating them. Compare total/per-product row counts,
   canonical row checksums, Unicode samples, aggregate ratings and boundary lengths.
7. Test the new image with MySQL: GetReviews, AddReview, restart persistence,
   two-replica visibility, readiness on DB failure, and backup/restore. Approve the
   immutable application image and matching DSN together, then resume traffic.
8. Watch errors, connection counts and readiness. Retain the old backup/PVC through
   the agreed rollback window. Resume normal GitOps reconciliation after acceptance.

## Rollback boundary

Before new writes reach MySQL, restore the previous application image AND its
PostgreSQL Secret/networking and retained database. Reverting only an image is
insufficient. After MySQL has accepted writes, PostgreSQL is stale: stop writes
and reconcile the new data before switching back. Do not promise a lossless
one-command rollback across database engines.

## Verification

Run the isolated Compose suite documented in `src/reviewsservice/README.md`.
Render all Kustomize overlays and Helm with database mode both disabled/enabled.
Run the reviews Docker build. These checks prove the code and configuration
change; they do not prove a live cloud deployment, existing-data transfer,
production TLS, offsite backup restoration or public GitHub publication.
