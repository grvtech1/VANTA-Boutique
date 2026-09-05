# Helm chart — vanta-boutique

Alternative to the Kustomize overlays for clusters where Helm is the packaging standard.
Derived from the upstream Online Boutique chart (Apache-2.0) and adapted: a `reviewsservice`
template, per-service image overrides, and cloud-neutral telemetry (no cloud-provider values,
SDKs or registries: all fourteen images come from `images.repository`, built by this repo's CI).

```sh
helm lint helm-chart
helm template vanta helm-chart | less

helm upgrade --install vanta helm-chart -n boutique --create-namespace \
  --set images.tag=<git-sha>   # the SHA the CD pipeline pinned in kustomize/overlays/staging
```

Useful values:

| Value | Default | Notes |
| --- | --- | --- |
| `images.repository` / `images.tag` | `docker.io/grvp1` / `latest` | all fourteen services; pin `tag` to a git SHA outside local loops |
| `images.overrides.<svc>.{repository,tag}` | — | canary one service from a different build |
| `reviewsService.replicas` | `1` | `>1` requires `reviewsService.database.enabled=true` (the chart refuses otherwise) |
| `reviewsService.database.enabled` | `false` | inject `DATABASE_URL` from Secret `reviews-db` (create it, or use the kustomize component) |
| `wishlistService.replicas` | `1` | must stay `1` — in-memory, per-pod store (the chart refuses `>1`) |
| `inventoryService.replicas` | `2` | read-only seeded stock; scales freely |
| `inventoryService.seed.configMap` | `""` | ConfigMap with `seed.json` (product id → quantity) to override the built-in stock |
| `networkPolicies.create` | `false` | deny-all + per-service allow policies |
| `telemetry.collectorAddr` | `""` | OTLP/gRPC collector address; set `telemetry.tracing=true` to emit traces |
| `frontend.platform` | `local` | UI banner only |

CI (`helm-lint-ci.yaml`) lints and renders the chart with default and hardened values.
