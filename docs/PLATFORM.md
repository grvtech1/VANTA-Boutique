# VANTA platform runbook

How to stand up VANTA Boutique on a **self-managed Kubernetes cluster on AWS** — from empty
cloud account to a GitOps-delivered, observable production platform — and how to run it day-2.
Everything is code; nothing is clicked in a console.

> **Just want to see the app?** Skip all of this and run it **free on local kind** — see
> [§8 Local alternative](#8-local-alternative-kind). This runbook is the AWS/production path.

---

## Architecture

```
Terraform ──▶ AWS VPC + 3× EC2 (1 master, 2 workers)
                     │  (user-data bootstraps containerd + kubeadm)
Ansible / bootstrap ─┘  kubeadm init/join + Calico CNI
                     │
ArgoCD (in-cluster) ─┴─ watches Git ──▶ syncs kustomize/overlays ──▶ app pods
Prometheus + Grafana + Alertmanager + Loki ─── scrape / collect ──▶ dashboards + alerts
```

| Layer | Tool | Path |
| --- | --- | --- |
| Infrastructure | Terraform | [`/terraform`](/terraform) |
| Cluster bootstrap | Ansible + `kubeadm` | [`/ansible`](/ansible), [`/scripts/bootstrap-k8s.sh`](/scripts/bootstrap-k8s.sh) |
| Delivery | ArgoCD app-of-apps (GitOps) + `promote.sh` | [`/argocd`](/argocd), [`/scripts/setup-argocd.sh`](/scripts/setup-argocd.sh), [`/scripts/promote.sh`](/scripts/promote.sh) |
| Entry | nginx Ingress + cert-manager TLS | [`/kustomize/components/ingress`](/kustomize/components/ingress), [`tls`](/kustomize/components/tls) |
| Observability | Prometheus/Grafana/Alertmanager/Loki + SLO alerts | [`/monitoring`](/monitoring) |
| App manifests | Kustomize (namespaced overlays) | [`/kustomize`](/kustomize) |
| Day-2 | Runbooks, chaos/failover drills, Velero | [`/docs/RUNBOOKS.md`](/docs/RUNBOOKS.md), [`/scripts`](/scripts), [`/backup`](/backup) |

---

## 0. Prerequisites

- An **AWS account** with credentials configured (`aws configure`) — default region `ap-south-1`.
- Local tools: **terraform ≥ 1.0**, **ansible**, **kubectl**, and **helm**.
- ~**$1.5/day** while running (1× `t3.small` + 2× `t3.micro`). Always `terraform destroy` when done.

---

## 1. Provision the infrastructure (Terraform)

Creates the VPC, public subnet, Internet Gateway, security groups, an SSH keypair, and 3 EC2
nodes. Each node's **user-data** installs `containerd`, `kubeadm`, `kubelet`, and `kubectl`.

```sh
cd terraform
terraform init
terraform plan        # always review first
terraform apply       # ~2–3 min; writes node IPs to outputs
terraform output      # master_ip, worker_ips, ssh command
```

> State, `*.tfvars`, and the generated `k8s-key.pem` are **git-ignored** — never commit them.

## 2. Form the cluster (Ansible + kubeadm)

Ansible waits for the user-data bootstrap to finish, runs `kubeadm init` on the master, installs
the **Calico** CNI, and `kubeadm join`s the workers.

```sh
cd ../ansible
# inventory.yml is templated from terraform outputs (master/worker IPs + key)
ansible-playbook -i inventory.yml playbook.yml
```

Fetch the kubeconfig and confirm all nodes are `Ready`:

```sh
scp -i ../terraform/k8s-key.pem ubuntu@<master_ip>:~/.kube/config ./kubeconfig-aws
export KUBECONFIG=$PWD/kubeconfig-aws
kubectl get nodes -o wide     # master + 2 workers, all Ready
```

> A scripted alternative to the playbook lives in
> [`scripts/bootstrap-k8s.sh`](/scripts/bootstrap-k8s.sh) (export `MASTER_IP`, `WORKER1_IP`,
> `WORKER2_IP` from `terraform output` first).

A fresh kubeadm cluster has **no default StorageClass** — the reviews MySQL PVC would stay
`Pending`. Install a provisioner once:

```sh
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## 3. Install ArgoCD (GitOps engine, app-of-apps)

```sh
cd ..
scripts/setup-argocd.sh        # installs ArgoCD (pinned) + registers argocd/root.yaml
kubectl -n argocd get applications
```

The root Application creates the environment Applications from [`argocd/apps/`](/argocd/apps):

| App | Path | Sync | Namespace |
| --- | --- | --- | --- |
| `vanta-boutique-staging` | `kustomize/overlays/staging` | **automatic** (prune + self-heal) | `boutique-staging` |
| `vanta-boutique-prod` | `kustomize/overlays/prod` | **manual** — approve in the UI or `scripts/sync-app.sh vanta-boutique-prod` | `boutique` |
| `vanta-boutique-dev` | `kustomize/overlays/dev` | automatic (for a kind cluster with ArgoCD) | `boutique` |

From here the app deploys itself: push → CI tests, builds, **scans (CRITICAL gate)**, SBOMs →
CD pushes `docker.io/grvp1/<svc>:<git-sha>` and **commits that SHA into the staging overlay** →
ArgoCD reconciles staging. Prod: `scripts/promote.sh <sha>` (or `--from-staging`) commits the
tag into the prod overlay → ArgoCD shows OutOfSync → a human syncs. **CI never holds cluster
credentials and never calls the ArgoCD API.**

## 4. Ingress + Observability

Secrets first (never in Git), then the stack — full detail in [`monitoring/README.md`](/monitoring/README.md):

```sh
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl -n monitoring create secret generic alertmanager-slack --from-literal=webhook='https://hooks.slack.com/services/...'

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack -n monitoring -f monitoring/prometheus-values.yml
helm upgrade --install loki grafana/loki-stack -n monitoring -f monitoring/loki-values.yml
kubectl apply -f monitoring/grafana/vanta-overview-dashboard.yaml

scripts/install-ingress-nginx.sh --provider helm     # NodePort 30080/30443 + metrics → SLO rules
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
```

`prometheus-values.yml` pins the stack to the master node, routes alerts by severity to
**Slack**, and ships **SRE rules** (pod/node/deployment health, HPA ceiling, reviews DB) plus an
**availability SLO (99.5%) with multi-window burn-rate alerts** computed from ingress-nginx
metrics. Grafana: `kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80`.

## 5. Reliability & security hardening

`kustomize/overlays/prod` composes it all: **default-deny NetworkPolicies**, **PDBs**,
**MySQL-backed reviews** (2 replicas + HPA), **nginx Ingress** with rate limits and
**cert-manager TLS** (edit the host in the overlay patch and the e-mail in
`components/tls/cluster-issuer.yaml`). Optional extras:

```sh
scripts/setup-rbac.sh            # least-privilege Roles/RoleBindings example
scripts/setup-pod-security.sh    # Pod Security standards
scripts/setup-hpa.sh             # metrics-server (HPAs need it)
VELERO_BUCKET=<bucket> backup/velero-install.sh   # 6-hourly namespace backups to S3
```

Practice failure (in **staging**, never prod) — and write down what you learned in
[`docs/RUNBOOKS.md`](/docs/RUNBOOKS.md):

```sh
NAMESPACE=boutique-staging scripts/chaos-engineering.sh   # kill pods, verify self-healing
NAMESPACE=boutique-staging scripts/failover-lab.sh        # cordon+drain a worker, watch rescheduling, curl the store
```

---

## 6. Day-2 operations

```sh
scripts/health-check.sh                                  # cluster + app health summary
scripts/promote.sh --from-staging && git push            # promote what staging runs → prod (then sync)
scripts/sync-app.sh vanta-boutique-prod                  # approve the prod sync
git revert <promotion-commit> && git push                # GitOps rollback (preferred; sync prod again)
kubectl rollout undo deployment/frontend -n boutique     # emergency only — then do the git revert
```

Incident playbooks (crash loops, node failover, DB down, SLO burn, TLS): [`docs/RUNBOOKS.md`](/docs/RUNBOOKS.md).

## 7. Teardown (stop the bill)

```sh
cd terraform
terraform destroy    # removes all AWS resources; cost → $0
```

## 8. Local alternative (kind)

No cloud account, no cost — the full app on a local
[kind](https://kind.sigs.k8s.io/) cluster:

```sh
kind create cluster --config kind-local.yaml
kubectl apply -k kustomize/overlays/dev
kubectl wait -n boutique --for=condition=ready pod --all --timeout=300s
kubectl port-forward -n boutique svc/frontend 8088:80     # http://localhost:8088  (or NodePort http://localhost:8888)
```

---

### One-time vs every-commit

| One-time setup | Every commit (automatic) | Release to prod (deliberate) |
| --- | --- | --- |
| `terraform apply` · `ansible-playbook` | `git push` | `scripts/promote.sh <sha>` |
| StorageClass · ingress-nginx · cert-manager | CI: test → build → **Trivy gate** → SBOM → validate manifests | `git push` |
| `setup-argocd.sh` (root app-of-apps) | CD: push `image:<sha>` → **commit SHA into staging** | ArgoCD prod → OutOfSync |
| monitoring stack + secrets | ArgoCD syncs staging → rolling update | human approves the sync |

New to this? The infra steps are **rare and deliberate**; the CI/CD loop is **constant and
hands-off**. Don't confuse the two.
