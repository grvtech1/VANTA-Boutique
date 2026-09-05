# Inventory Service

Reports **stock levels** per product so the storefront can show *in stock*,
*only N left* and *sold out* on the catalog and product pages. Read-only from
the storefront's point of view; quantities are seeded at startup.

## API (see `../../protos/demo.proto`)

| RPC         | Request            | Response            |
|-------------|--------------------|---------------------|
| `GetStock`  | `GetStockRequest`  | `StockLevel`        |
| `ListStock` | `ListStockRequest` | `ListStockResponse` |

`StockLevel.status` is derived on the server so every client agrees on what
"low" means: `OUT_OF_STOCK` at zero, `LOW_STOCK` at or below
`LOW_STOCK_THRESHOLD`, otherwise `IN_STOCK`. `GetStock` for an unknown product
returns `NOT_FOUND`; `ListStock` skips unknown IDs and, with no IDs, returns
everything (sorted by product ID).

## Seed data

- Built-in table mirroring `productcatalogservice/products.json`, with a few
  items deliberately low or sold out so every state is visible on day one.
- Or set `INVENTORY_SEED_FILE` to a JSON object of `{"<product id>": <qty>}` —
  in Kubernetes, mount it from a ConfigMap to change stock without a rebuild.

## Configuration

| Variable                 | Default | Purpose                                   |
|--------------------------|---------|-------------------------------------------|
| `PORT`                   | 50053   | gRPC listen port                          |
| `LOG_LEVEL`              | info    | logrus level                              |
| `LOW_STOCK_THRESHOLD`    | 5       | quantities at or below this are LOW_STOCK |
| `INVENTORY_SEED_FILE`    | (none)  | JSON seed override                        |
| `MAX_IDS_PER_REQUEST`    | 200     | cap on `ListStock` IDs                    |
| `MAX_RECV_MSG_BYTES`     | 262144  | gRPC max inbound message size             |
| `SHUTDOWN_GRACE_SECONDS` | 20      | drain budget on SIGTERM                   |

## Develop

```sh
./genproto.sh
go mod tidy
go vet ./... && go test -race ./...
PORT=50053 go run .
```

Health is exposed over the standard gRPC health protocol (used by the
Kubernetes probes), and reflection is enabled so `grpcurl` can introspect it.
