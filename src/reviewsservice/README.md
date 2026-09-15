# Reviews Service

Serves product reviews and ratings over gRPC. A customer can read all reviews
for a product (with the aggregate average rating) and submit a new 1–5 star
review with a comment.

Added to the demo to show building and integrating a brand-new microservice
into the existing polyglot gRPC mesh, end-to-end: proto → service → container →
Kubernetes → CI/CD.

## API (see `../../protos/demo.proto`)

| RPC          | Request              | Response              |
|--------------|----------------------|-----------------------|
| `GetReviews` | `GetReviewsRequest`  | `GetReviewsResponse`  |
| `AddReview`  | `AddReviewRequest`   | `AddReviewResponse`   |

## Storage

Two `Store` implementations sit behind one interface:

- **In-memory** (default) — concurrency-safe, bounded, seeded at startup. Zero
  dependencies, but per-process: run a **single replica** (data is not durable
  and not shared across pods).
- **MySQL** (set `DATABASE_URL`) — durable and shared, so reviewsservice
  can run multiple replicas and an HPA. Schema is created on startup; the gRPC
  health status follows DB connectivity. Enable it in Kubernetes with the
  `kustomize/components/reviews-persistence` component (provisions MySQL + a
  PVC and injects `DATABASE_URL`). Needs a default StorageClass for the PVC.
  The bundled MySQL instance is single-node demo infrastructure, not an HA database.

## Develop

```sh
# 1. Generate gRPC stubs (needs protoc + protoc-gen-go + protoc-gen-go-grpc)
./genproto.sh

# 2. Resolve dependencies and create go.sum
go mod tidy

# 3. Test and run
go test ./...
PORT=50051 go run .
```

## Try it (with grpcurl, reflection is enabled)

```sh
grpcurl -plaintext -d '{"product_id":"OLJCESPC7Z"}' \
  localhost:50051 hipstershop.ReviewsService/GetReviews

grpcurl -plaintext -d '{"product_id":"OLJCESPC7Z","author":"Sam","rating":5,"comment":"Love it"}' \
  localhost:50051 hipstershop.ReviewsService/AddReview
```

## Environment

| Variable                  | Default | Purpose                                         |
|---------------------------|---------|-------------------------------------------------|
| `PORT`                    | `50051` | gRPC listen port                                |
| `DATABASE_URL`            | (unset) | MySQL driver DSN; when set, uses the durable store  |
| `LOG_LEVEL`               | `info`  | logrus level (`debug`/`info`/`warn`/`error`)    |
| `MAX_AUTHOR_LEN`          | `80`    | max review author length                        |
| `MAX_COMMENT_LEN`         | `1000`  | max review comment length                       |
| `MAX_REVIEWS_PER_PRODUCT` | `500`   | return limit in MySQL; retention cap in memory |
| `MAX_RECV_MSG_BYTES`      | `1048576` | max gRPC request size (1 MiB)                  |
| `SHUTDOWN_GRACE_SECONDS`  | `20`    | graceful-shutdown drain window                  |

`DATABASE_URL` keeps its existing environment-variable name, but now takes a Go
MySQL driver DSN, not a `postgres://` or `mysql://` URL:

```text
reviews:password@tcp(reviews-mysql:3306)/reviews?charset=utf8mb4&tls=false
```

`tls=false` is for the isolated demo only. For a trusted CA-signed endpoint, use
its DNS hostname and `tls=true` (verified certificates); never `skip-verify`.
The database must already exist. Startup creates the table; the application
account needs CREATE, SELECT and INSERT on this database, not global privileges.
The pool is bounded to 10 connections per replica; account for all HPA replicas
when sizing the database. Dial/read/write timeouts default to 5 seconds.

From the repository root, run real MySQL tests without exposing a host port:

```sh
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml up --abort-on-container-exit --exit-code-from tests
docker compose -p vanta-reviews-test -f src/reviewsservice/compose.test.yaml down -v
```

Tests cover persistence across pools, RPC round-trips, concurrent writers,
Unicode, SQL parameters, case-sensitive IDs, query limits and rating constraints.
Without `TEST_DATABASE_URL`, database tests skip. CI sets `REQUIRE_MYSQL_TESTS=1`
so a missing DSN fails instead. See [cutover guidance](../../docs/REVIEWS_MYSQL_MIGRATION.md)
before updating any existing PostgreSQL-backed deployment.
