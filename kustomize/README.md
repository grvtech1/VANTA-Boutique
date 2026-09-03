# Kustomize layout

```
kustomize/
├── base/         one Deployment + Service (+ ServiceAccount) per microservice — the source of truth
├── overlays/
│   ├── dev/          kind / single node · namespace boutique · NodePort 30080 · floating `latest` tags
│   ├── kind-ingress/ dev + nginx Ingress (http://vanta.local)
│   ├── staging/      namespace boutique-staging · 2 replicas · Postgres reviews · SHA tags bumped by CD
│   └── prod/         namespace boutique · 3 replicas · netpol + PDB + Postgres + Ingress + TLS · SHA tags via promote.sh
├── components/   opt-in slices, composable in any overlay
│   ├── ingress/               nginx Ingress with rate limits
│   ├── tls/                   cert-manager ClusterIssuer + TLS patch on the Ingress
│   ├── network-policies/      default-deny + explicit allow per service (incl. reviews-db)
│   ├── pod-disruption-budgets/ PDBs for multi-replica services
│   ├── reviews-persistence/   Postgres + PVC + Secret for reviewsservice
│   ├── redis-persistence/     PVC-backed Redis cart
│   ├── service-mesh-istio/    Istio gateway variant
│   ├── tracing/               Jaeger + OpenTelemetry collector
│   ├── container-images-*/    swap registry / tag suffix for every image
│   ├── custom-base-url/, non-public-frontend/, single-shared-session/, without-loadgenerator/
└── tests/        render combinations checked in CI
```

## Render locally

```sh
kubectl kustomize kustomize/overlays/dev | less
kubectl kustomize kustomize/overlays/prod > /tmp/prod.yaml   # what ArgoCD would apply
```

## Images

Only the services this repo rebuilds (`frontend`, `productcatalogservice`, `reviewsservice`)
point at `docker.io/grvp1`. Everything else pulls the unmodified upstream image — we do not
rebuild what we did not change. Tags:

| Overlay | Tag policy |
| --- | --- |
| dev | `latest` — local inner loop only |
| staging | git SHA, written by the CD pipeline (`scripts/bump-image-tags.sh`) |
| prod | git SHA, written by `scripts/promote.sh <sha>` and applied by a manual ArgoCD sync |

## Adding a component

1. Create `components/<name>/kustomization.yaml` (`kind: Component`).
2. Reference it from an overlay under `components:`.
3. Add a render test under `tests/`.
