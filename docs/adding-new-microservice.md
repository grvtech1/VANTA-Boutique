# Adding a new microservice

`reviewsservice` is the worked example — every step below has a real counterpart in the repo.

| Step | What | Example |
| --- | --- | --- |
| 1 | **Contract** — add messages + RPCs to `protos/demo.proto`, regenerate stubs | `GetReviews`, `AddReview` |
| 2 | **Code** — `src/<name>/` with gRPC health, graceful shutdown, input caps | [`src/reviewsservice`](/src/reviewsservice) |
| 3 | **Dockerfile** — multi-stage, `distroless:nonroot`, no secrets baked in | `src/reviewsservice/Dockerfile` |
| 4 | **Base manifest** — Deployment + Service + ServiceAccount with probes, requests/limits, non-root securityContext | `kustomize/base/reviewsservice.yaml` + entry in `kustomize/base/kustomization.yaml` |
| 5 | **Overlays** — replicas per env; image entry (`newName: docker.io/grvp1/<name>`) in dev/staging/prod | `kustomize/overlays/*/kustomization.yaml` |
| 6 | **Security** — NetworkPolicy (and one for any datastore it owns) | `components/network-policies/network-policy-reviewsservice.yaml`, `…-reviews-db.yaml` |
| 7 | **Resilience** — PDB if it runs ≥ 2 replicas; HPA if it scales on CPU | `components/pod-disruption-budgets/pdbs.yaml`, `overlays/prod/hpa-reviews.yaml` |
| 8 | **Helm** — template + values block | `helm-chart/templates/reviewsservice.yaml`, `values.yaml` → `reviewsService` |
| 9 | **CI** — add to the build/scan matrix (`ci-pipeline.yml`) and to the CD push matrix + `scripts/bump-image-tags.sh` default list | matrix `service:` entries |
| 10 | **Frontend wiring** — env var `<NAME>_SERVICE_ADDR` in the frontend manifests/template | `REVIEWS_SERVICE_ADDR` |
| 11 | **Observability** — alert if it owns state; add to the dashboard if it is on the request path | `ReviewsDatabaseDown` |
| 12 | **Docs** — README service table + architecture diagram; a runbook entry for its failure mode | `docs/RUNBOOKS.md` |

Render tests (`kustomize/tests/`) and `helm-lint-ci` will fail fast if steps 4–8 are inconsistent.
