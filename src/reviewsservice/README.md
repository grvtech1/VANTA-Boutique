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

Data is held in a concurrency-safe in-memory store seeded at startup. The
`list`/`add` methods are the seam for swapping in a real database later.

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

| Variable | Default | Purpose                |
|----------|---------|------------------------|
| `PORT`   | `50051` | gRPC listen port       |
