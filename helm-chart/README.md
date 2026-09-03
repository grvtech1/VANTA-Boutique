# Helm chart — vanta-boutique

Alternative to the Kustomize overlays for clusters where Helm is the packaging standard.
Derived from the upstream Online Boutique chart (Apache-2.0) and adapted: a `reviewsservice`
template, per-service image overrides, and cloud-neutral telemetry (no GCP-specific values).

```sh
helm lint helm-chart
helm template vanta helm-chart | less

helm upgrade --install vanta helm-chart -n boutique --create-namespace \
  --set images.overrides.frontend.tag=<git-sha> \
  --set images.overrides.productcatalogservice.tag=<git-sha> \
  --set images.overrides.reviewsservice.tag=<git-sha>
```

Useful values:

| Value | Default | Notes |
| --- | --- | --- |
| `images.overrides.<svc>.{repository,tag}` | `docker.io/grvp1/<svc>:latest` | the 3 services this repo rebuilds; pin `tag` to a git SHA |
| `images.repository` / `images.tag` | upstream / `appVersion` | unmodified upstream services |
| `reviewsService.replicas` | `1` | `>1` requires `reviewsService.database.enabled=true` (the chart refuses otherwise) |
| `reviewsService.database.enabled` | `false` | inject `DATABASE_URL` from Secret `reviews-db` (create it, or use the kustomize component) |
| `networkPolicies.create` | `false` | deny-all + per-service allow policies |
| `telemetry.collectorAddr` | `""` | OTLP/gRPC collector address; set `telemetry.tracing=true` to emit traces |
| `frontend.platform` | `local` | UI banner only |

CI (`helm-lint-ci.yaml`) lints and renders the chart with default and hardened values.
