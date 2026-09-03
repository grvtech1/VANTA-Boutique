# Kustomize render tests

Each sub-directory is a combination of components that must keep rendering. CI
([`kustomize-build-ci.yaml`](../../.github/workflows/kustomize-build-ci.yaml)) runs
`kubectl kustomize` over every overlay **and** every directory here on each change.

| Test | Composes |
| --- | --- |
| `hardened/` | base + network-policies + pod-disruption-budgets + reviews-persistence + ingress (what prod uses) |
| `tls-ingress/` | ingress + tls (cert-manager patch ordering) |

Add a directory here whenever you add a component — a render failure in CI is cheaper than an
ArgoCD sync failure at 2 AM.
