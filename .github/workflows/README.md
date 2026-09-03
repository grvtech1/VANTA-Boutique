# CI/CD workflows

```
git push (main / feature / PR)
   │
   ▼
ci-pipeline.yml ─ lint → unit tests → reviews -race tests (Postgres) → build image
                  → Trivy CRITICAL gate (blocking) + HIGH report → CycloneDX SBOM
                  → kustomize + helm render validation
   │  (main only, on success)
   ▼
cd-pipeline.yml ─ build → push docker.io/grvp1/<svc>:<git-sha> (no :latest)
                  → commit the SHA into kustomize/overlays/staging  [skip ci]
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
| `terraform-validate-ci.yaml` | changes under `terraform/` | `terraform validate` |

Design notes: the pipeline never holds cluster credentials (pull-based GitOps); images are
tagged with the git SHA only; the same flow is mirrored for Jenkins in [`/Jenkinsfile`](/Jenkinsfile).
Secrets required in the repo: `DOCKER_USERNAME`, `DOCKER_PASSWORD`.
