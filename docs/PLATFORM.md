# 🛠 VANTA Platform Runbook

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
| Delivery | ArgoCD (GitOps) | [`/argocd`](/argocd), [`/scripts/setup-argocd.sh`](/scripts/setup-argocd.sh) |
| Observability | Prometheus/Grafana/Loki | [`/monitoring`](/monitoring) |
| App manifests | Kustomize | [`/kustomize`](/kustomize) |

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

> A scripted, idempotent alternative to the playbook lives in
> [`scripts/bootstrap-k8s.sh`](/scripts/bootstrap-k8s.sh) (+ `multi-node-setup.sh`).

## 3. Install ArgoCD (GitOps engine)

```sh
../scripts/setup-argocd.sh                 # installs ArgoCD into the argocd namespace
kubectl apply -f ../argocd/application-staging.yaml   # staging: auto-sync
kubectl apply -f ../argocd/application-prod.yaml       # prod: manual sync + prune
```

- **staging** (`kustomize/overlays/staging`) **auto-syncs** on every Git change.
- **prod** (`kustomize/overlays/prod`) is **manual sync** with prune + retry/backoff — nothing
  reaches prod without explicit approval in the ArgoCD UI or `argocd app sync`.

From here the app deploys itself: push a change → CI builds/scans/pushes the image and bumps the
tag in Git → ArgoCD reconciles. **CI never holds cluster credentials.**

## 4. Observability (Prometheus + Grafana + Loki)

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yml
helm upgrade --install loki grafana/loki-stack \
  -n monitoring -f monitoring/loki-values.yml
```

`prometheus-values.yml` pins the stack to the master node, enables **Alertmanager**, and ships
**SRE alert rules** (pod crash-loop, node health, deployment replica mismatch). Reach Grafana:

```sh
kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80   # http://localhost:3000
```

## 5. Reliability & security hardening (optional SRE scripts)

```sh
../scripts/setup-rbac.sh            # least-privilege Roles/RoleBindings
../scripts/setup-pod-security.sh    # Pod Security standards
../scripts/setup-hpa.sh             # Horizontal Pod Autoscalers
kubectl apply -k kustomize/overlays/prod   # includes NetworkPolicies + PodDisruptionBudgets
```

Practice failure (in **staging**, never prod):

```sh
../scripts/chaos-engineering.sh     # kill random pods, verify self-healing
../scripts/failover-lab.sh          # drain a node, watch rescheduling
```

---

## 6. Day-2 operations

```sh
../scripts/health-check.sh          # cluster + app health summary
kubectl rollout undo deployment/frontend -n boutique   # emergency rollback
git revert <bad-commit> && git push                    # GitOps rollback (preferred)
```

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
kubectl wait --for=condition=ready pod --all --timeout=300s
kubectl port-forward --address 0.0.0.0 svc/frontend-external 8088:80   # http://localhost:8088
```

---

### One-time vs every-commit

| One-time setup | Every commit (automatic) |
| --- | --- |
| `terraform apply` · `ansible-playbook` | `git push` |
| install Calico CNI | CI: test → build → Trivy scan → push image |
| `setup-argocd.sh` + Applications | CI commits new image tag to Git |
| install monitoring stack | ArgoCD syncs → rolling update |

New to this? The infra steps are **rare and deliberate**; the CI/CD loop is **constant and
hands-off**. Don't confuse the two.
