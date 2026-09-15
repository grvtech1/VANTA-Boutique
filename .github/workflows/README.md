# CI/CD workflows

```
git push (main / feature / PR)
   │
   ▼
ci-pipeline.yml ─ go vet + unit tests (4 Go services) → reviews -race tests (MySQL)
                  → build ALL 14 images → Trivy CRITICAL gate (blocking) + HIGH report
                  → CycloneDX SBOM per image → kustomize + helm render validation
   │  (main only, on success)
   ▼
cd-pipeline.yml ─ build → push docker.io/grvp1/<svc>:<git-sha> for all 14 (no :latest)
                  → commit the SHAs into kustomize/overlays/staging  [skip ci]
   │
   ▼
ArgoCD (in cluster) ─ sees the Git change → syncs staging.  Prod: scripts/promote.sh + manual sync.
```

| Workflow | Runs when | Purpose |
| --- | --- | --- |
| `ci-pipeline.yml` | push main/feature/hotfix, PR → main | test, build, **scan gate**, SBOM, manifest validation |
| `cd-pipeline.yml` | `workflow_run` of CI succeeded on `main` | push immutable images, GitOps-promote **staging** |
| `kustomize-build-ci.yaml` | changes under `kustomize/` | every overlay + test combination must render |
| `helm-lint-ci.yaml` | changes under `helm-chart/` | `helm lint` + `helm template` (default + hardened values) |
| `deps-bump.yml` | manual (`gh workflow run deps-bump.yml`) | bump Go modules to minimum fixed versions, build/vet, commit, then dispatch CI (GITHUB_TOKEN pushes never trigger push workflows) |
| `terraform-validate-ci.yaml` | changes under `terraform/` | `terraform validate` |

Design notes: the pipeline never holds cluster credentials (pull-based GitOps); images are
tagged with the git SHA only; every image that runs in a cluster is built, scanned and pushed
by this repo — there is no runtime dependency on an upstream or cloud-provider registry.
Secrets required in the repo: `DOCKER_USERNAME`, `DOCKER_PASSWORD`.
