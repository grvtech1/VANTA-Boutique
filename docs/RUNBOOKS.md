# 🚑 Runbooks

Incident playbooks for VANTA Boutique. Every alert in `monitoring/` links here. The order is
always the same: **confirm scope → what changed? → mitigate → then root-cause.**

Golden rule: *mitigate first, diagnose later.* A rollback is a `git revert` + sync — cheap.

---

## Pod CrashLooping / PodNotReady

**Alert:** `PodCrashLooping`, `PodNotReady` · **Dashboard:** Overview → restarts, ready ratio

1. Scope: one pod, one service, or everything?
   ```sh
   kubectl get pods -n boutique -o wide
   kubectl describe pod <pod> -n boutique | sed -n '/Events/,$p'
   kubectl logs <pod> -n boutique --previous
   ```
2. What changed? Compare the running image with the last promotion commit:
   ```sh
   kubectl get deploy <svc> -n boutique -o jsonpath='{.spec.template.spec.containers[0].image}'
   git log --oneline -5 -- kustomize/overlays/prod/kustomization.yaml
   ```
3. Mitigate: if a new tag correlates → **rollback** (see below). If `OOMKilled` → raise the
   limit in the overlay. If readiness fails on a dependency (e.g. reviewsservice ↔ reviews-db)
   → fix the dependency first; readiness has already pulled the pod out of the Service.
4. Prevent: add the failure mode to a probe or an alert.

## Bad deploy → rollback (GitOps)

The desired state lives in Git, so rolling back is a Git operation. `kubectl rollout undo`
alone creates **drift**: ArgoCD (staging auto-sync) would re-apply the bad tag.

```sh
# staging (auto-sync): revert the CD promotion commit
git revert <ci-gitops-commit> && git push          # ArgoCD syncs the previous SHA
# prod (manual sync): revert the promote commit, then approve
git revert <release-prod-commit> && git push && scripts/sync-app.sh vanta-boutique-prod
# emergency only, then IMMEDIATELY follow with the git revert above:
kubectl rollout undo deployment/frontend -n boutique
```

## Node NotReady / failover

**Alert:** `NodeNotReady` · **Drill:** `scripts/failover-lab.sh`

1. `kubectl get nodes -o wide`; `kubectl describe node <n>` (conditions, pressure, kubelet).
2. Pods on a NotReady node are rescheduled after the eviction timeout (~5 min). PDBs guarantee
   `minAvailable: 1` during **voluntary** drains, not crashes — replicas ≥ 2 do that.
3. Mitigate: `kubectl cordon <n>`; if the node is gone for good, `kubectl delete node <n>` so
   the scheduler stops waiting. On EC2 check the instance status / EIP.
4. Gotcha: a `minAvailable: 1` PDB on a **single-replica** Deployment blocks `drain` forever.

## reviews-db down

**Alert:** `ReviewsDatabaseDown` · reviewsservice health follows DB connectivity, so its pods
go NotReady and the frontend hides reviews (the rest of the store keeps working).

```sh
kubectl get pods,pvc -n boutique -l app=reviews-db
kubectl describe pvc reviews-db -n boutique       # Pending? → no default StorageClass
kubectl logs deploy/reviews-db -n boutique
```
No StorageClass on a fresh kubeadm cluster is the classic cause — install a provisioner
(e.g. rancher local-path) or set `storageClassName` explicitly. Restore data with Velero
(`velero restore create --from-backup <name>`).

## HPA maxed out

**Alert:** `HpaMaxedOut` · **Dashboard:** HPA current vs max

1. Is it real load or a bug spinning CPU? `kubectl top pods -n boutique`; check ingress RPS.
2. Real load → raise `maxReplicas` in the overlay (Git) and/or add a worker (Terraform
   `worker_count`). Bug → find the hot pod, roll back.
3. Remember the HPA needs `metrics-server` (`scripts/setup-hpa.sh`).

## Ingress 5xx / SLO burn

**Alert:** `SLOErrorBudgetBurnFast` (page) / `SLOErrorBudgetBurnSlow` (ticket)

1. RED first: which status codes, since when (Overview → requests by status).
   `kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=200 | grep ' 5[0-9][0-9] '`
2. 503 = no healthy backend: `kubectl get endpoints frontend -n boutique` — empty means the
   frontend pods are not Ready (see CrashLooping). 502/504 = backend slow or dead.
3. With NetworkPolicies on, confirm the frontend policy admits traffic from the
   `ingress-nginx` namespace. Then USE: CPU/memory/pool saturation on frontend & checkout.
4. What changed? Tag promotions, Ingress annotation changes, cert renewals.

## Certificate expiry / TLS

`kubectl get certificate,order,challenge -A` — cert-manager renews 30 days before expiry.
Stuck challenge → the HTTP-01 path must be reachable on port 80 through the Ingress; check the
`ClusterIssuer` email/server and rate limits (use `letsencrypt-staging` while testing).

## Backup / restore drill (quarterly)

```sh
velero backup create drill-$(date +%F) --include-namespaces boutique
kubectl delete deploy reviews-db -n boutique               # simulate loss
velero restore create --from-backup drill-$(date +%F)
kubectl get pods -n boutique -w
```
