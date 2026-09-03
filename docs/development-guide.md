# Development guide (local, kind)

## Prerequisites

- Docker, [kind](https://kind.sigs.k8s.io/), `kubectl`, `helm` (optional: `make` on Linux/macOS/WSL)
- Go 1.25+ for the Go services, .NET 8 for cartservice, Node 20 / Python 3.12 for the others

## 1. Cluster + app

```sh
kind create cluster --config kind-local.yaml          # or: make kind-up
kubectl apply -k kustomize/overlays/dev               # or: make deploy
kubectl wait -n boutique --for=condition=ready pod --all --timeout=300s
# http://localhost:8888   (NodePort)   or   kubectl port-forward -n boutique svc/frontend 8088:80
```

Optional nginx Ingress (what prod uses):

```sh
scripts/install-ingress-nginx.sh --provider kind      # or: make ingress
kubectl apply -k kustomize/overlays/kind-ingress
echo "127.0.0.1 vanta.local" | sudo tee -a /etc/hosts   # → http://vanta.local
```

## 2. Change a service, see it in the cluster

```sh
docker build -t docker.io/grvp1/reviewsservice:dev src/reviewsservice
kind load docker-image docker.io/grvp1/reviewsservice:dev --name boutique
kubectl set image deployment/reviewsservice server=docker.io/grvp1/reviewsservice:dev -n boutique
kubectl rollout status deployment/reviewsservice -n boutique
```

(`dev` overlay uses `latest` on purpose; staging/prod are pinned to git SHAs by CI.)

## 3. Tests

```sh
cd src/reviewsservice && go vet ./... && go test -race ./...
# Postgres-backed tests:
docker run -d --rm --name reviews-pg -e POSTGRES_DB=reviews -e POSTGRES_USER=reviews \
  -e POSTGRES_PASSWORD=reviews -p 5432:5432 postgres:16-alpine
TEST_DATABASE_URL=postgres://reviews:reviews@localhost:5432/reviews?sslmode=disable go test -race ./...
```

## 4. Render what ArgoCD would apply

```sh
kubectl kustomize kustomize/overlays/prod | less
helm template vanta helm-chart --set networkPolicies.create=true | less
```

## 5. Durable reviews store

Add to `kustomize/overlays/dev/kustomization.yaml`:

```yaml
components:
  - ../../components/reviews-persistence
```

kind ships a default StorageClass (`standard`), so the PVC binds immediately.

## Clean up

```sh
kind delete cluster --name boutique                   # or: make kind-down
```
