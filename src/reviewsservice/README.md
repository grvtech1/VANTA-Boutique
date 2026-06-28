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
- **PostgreSQL** (set `DATABASE_URL`) — durable and shared, so reviewsservice
  can run multiple replicas and an HPA. Schema is created on startup; the gRPC
  health status follows DB connectivity. Enable it in Kubernetes with the
  `kustomize/components/reviews-persistence` component (provisions Postgres + a
  PVC and injects `DATABASE_URL`). Needs a default StorageClass for the PVC.

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
| `DATABASE_URL`            | (unset) | Postgres DSN; when set, uses the durable store  |
| `LOG_LEVEL`               | `info`  | logrus level (`debug`/`info`/`warn`/`error`)    |
| `MAX_AUTHOR_LEN`          | `80`    | max review author length                        |
| `MAX_COMMENT_LEN`         | `1000`  | max review comment length                       |
| `MAX_REVIEWS_PER_PRODUCT` | `500`   | cap on reviews returned/retained per product    |
| `MAX_RECV_MSG_BYTES`      | `1048576` | max gRPC request size (1 MiB)                  |
| `SHUTDOWN_GRACE_SECONDS`  | `20`    | graceful-shutdown drain window                  |

Integration test: set `TEST_DATABASE_URL` to run `TestPgStore` against a real
PostgreSQL (skipped otherwise).

