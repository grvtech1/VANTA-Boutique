# Wishlist Service

Keeps each shopper's **saved items** server-side, keyed by the session ID the
frontend already issues. Before this service the wishlist lived only in the
browser's `localStorage`; now it survives a cleared browser and follows the
session. The storefront still falls back to `localStorage` when the service is
not configured, so the feature degrades instead of breaking.

## API (see `../../protos/demo.proto`)

| RPC           | Request                     | Response   |
|---------------|-----------------------------|------------|
| `GetWishlist` | `GetWishlistRequest`        | `Wishlist` |
| `AddItem`     | `AddWishlistItemRequest`    | `Wishlist` |
| `RemoveItem`  | `RemoveWishlistItemRequest` | `Wishlist` |

Every call returns the full, current list (newest first) so the client can
repaint from one response. `AddItem` is idempotent; `RemoveItem` of something
that is not there is a no-op — both are safe to retry.

## Storage

An in-memory store behind a `Store` interface, bounded on two axes so a hostile
or runaway client cannot grow memory without limit:

- `MAX_ITEMS_PER_USER` (default 200) — oldest saved item is evicted.
- `MAX_USERS` (default 20000) — least-recently-touched list is evicted.

State is per-process and not shared across replicas: run a **single replica**.
A shared store (Redis or Postgres) can be dropped in behind the same interface
when horizontal scaling is needed; that is the same seam `reviewsservice` uses.

## Configuration

| Variable                 | Default | Purpose                              |
|--------------------------|---------|--------------------------------------|
| `PORT`                   | 50052   | gRPC listen port                     |
| `LOG_LEVEL`              | info    | logrus level                         |
| `MAX_ITEMS_PER_USER`     | 200     | per-user cap                         |
| `MAX_USERS`              | 20000   | total lists kept in memory           |
| `MAX_ID_LEN`             | 64      | cap on user/product ID length        |
| `MAX_RECV_MSG_BYTES`     | 262144  | gRPC max inbound message size        |
| `SHUTDOWN_GRACE_SECONDS` | 20      | drain budget on SIGTERM              |

## Develop

```sh
./genproto.sh          # regenerate stubs (protoc + protoc-gen-go + protoc-gen-go-grpc)
go mod tidy
go vet ./... && go test -race ./...
PORT=50052 go run .
```

Health is exposed over the standard gRPC health protocol (used by the
Kubernetes probes), and reflection is enabled so `grpcurl` can introspect it.
