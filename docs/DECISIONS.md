# Architecture decisions (ADR-lite)

Short records of the non-obvious choices in this platform and *why* — the part that matters
in a review or an interview.

| # | Decision | Why | Trade-off accepted |
| --- | --- | --- | --- |
| 1 | **Pull-based GitOps (ArgoCD in-cluster)**, CI only commits to Git | CI never holds cluster credentials; drift is corrected continuously; every deploy is a commit (audit + `git revert` rollback) | ArgoCD is one more component to run and upgrade |
| 2 | **Immutable image tags = git SHA; no `:latest`** in staging/prod | "What is running?" is answerable; a re-pushed `:latest` produces no Git diff, so ArgoCD would never redeploy | dev keeps `latest` for the local inner loop, explicitly documented |
| 3 | **staging auto-sync, prod manual sync** | Every green build lands in staging automatically; prod needs a human decision (`promote.sh` + sync) | Two-step release, on purpose |
| 4 | **App-of-apps** root Application | Environments are declared in Git; adding one is a file, not a click | Root app itself is registered once by hand |
| 5 | **Rebuild only the services we changed** (frontend, productcatalog, reviews); others use upstream images | Smaller CI, honest provenance; upstream images are public and pinned to `v0.10.5` | Two registries in the manifests |
| 6 | **Trivy CRITICAL (fixable) is a hard gate; HIGH is reported** | Blocks what ships without blocking on vulnerabilities that have no fix yet | A new CRITICAL in a base image can block a release until rebased |
| 7 | **Kustomize for delivery, Helm as an alternative package** | ArgoCD + overlays keep environment diffs explicit; Helm serves clusters standardised on charts | Two manifest sources to keep in sync (CI validates both) |
| 8 | **nginx Ingress + rate limits in front of the frontend**; NodePort only for dev | Single entry point, TLS termination via cert-manager, request metrics for the SLO | An ingress controller to operate |
| 9 | **Default-deny NetworkPolicies in prod** with per-service allow lists | Blast radius: a compromised pod cannot reach the database or other services it does not need | Every new service needs a policy (the render test catches missing ones early) |
| 10 | **SLO + multi-window burn-rate alerts** instead of raw thresholds | Pages on user-visible impact rate, not on every blip; fast window pages, slow window tickets | Needs ingress metrics; meaningless without traffic |
| 11 | **Secrets never in Git** (Grafana admin, Slack webhook, Velero creds, kubeconfig) | The repo is public | Slightly more setup steps (documented in `monitoring/README.md`) |
| 12 | **Reviews store: in-memory by default, Postgres opt-in** | Zero-dependency dev experience; durability and multi-replica where it matters | The chart refuses `replicas>1` without the database to prevent split data |
| 13 | **Self-managed kubeadm on EC2 instead of EKS** | Learning the control plane hands-on (certs, etcd, CNI, StorageClass) and ~$1.5/day vs the EKS control-plane fee | We own upgrades, HA and backups ourselves |
| 14 | **Keep upstream attribution and license headers** | Apache-2.0 requires it, and honesty about origin is part of the portfolio | — |
