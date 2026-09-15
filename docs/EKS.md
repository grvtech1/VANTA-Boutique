# EKS Deployment Runbook

How to stand up VANTA Boutique on **AWS EKS** — a second deployment target in the same repo
alongside the self-managed kubeadm cluster. Same app, same images, different infrastructure
philosophy.

> **Cost warning:** EKS control plane ~$0.10/hr + 2× t3.large nodes ~$0.14/hr + NAT gateway
> ~$0.045/hr + ALB (pay-per-request). A running cluster costs roughly **$6–7/day**.
> Always `terraform destroy` when done.

---

## Architecture

```
Terraform (terraform-eks/) ──▶ AWS VPC (10.10.0.0/16, 2 AZs)
                                    │
                               EKS managed control plane (AWS-owned, HA across 3 AZs)
                                    │
                          Managed node group (2× t3.large, private subnets)
                                    │
                    ┌───────────────┴──────────────────┐
                    │                                  │
            AWS Load Balancer Controller         EBS CSI Driver (addon)
            (Helm, kube-system)                  (gp3 volumes for MySQL PVC)
                    │
              ALB (internet-facing, public subnets)
                    │
             kustomize/overlays/eks ──▶ boutique namespace (14 services)
```

| Layer | Tool | Path |
| --- | --- | --- |
| Infrastructure | Terraform (EKS modules) | `terraform-eks/` |
| Cluster add-ons | Shell script (Helm: LB Controller) | `scripts/eks-addons.sh` |
| Entry point | AWS ALB via Ingress (AWS LB Controller) | `kustomize/overlays/eks/ingress.yaml` |
| Persistent volumes | EBS gp3 (EBS CSI addon) | `kustomize/overlays/eks/gp3-storageclass.yaml` |
| App manifests | Kustomize overlay | `kustomize/overlays/eks/` |
| GitOps (optional) | ArgoCD Application (manual sync) | `argocd/apps/eks.yaml` |

---

## What differs from the kubeadm stack

| Concern | kubeadm (`terraform/`) | EKS (`terraform-eks/`) |
| --- | --- | --- |
| Control plane | Self-managed on EC2 — you run etcd, kube-apiserver, upgrades | Managed by AWS — HA across 3 AZs, auto-patched |
| StorageClass | `local-path` (hostPath, node-local) | EBS `gp3` via EBS CSI driver — real snapshots |
| Ingress | nginx Ingress (NodePort 30080/30443) | AWS ALB via AWS Load Balancer Controller |
| CNI | Calico (overlay network, 192.168.0.0/16) | VPC CNI (pods get VPC IPs, no overlay) |
| Pod → AWS auth | Node instance profile (broad) | IRSA (per-SA IAM roles, least privilege) |
| VPC CIDR | 10.0.0.0/16 | 10.10.0.0/16 (different → VPC peering safe) |
| Cost | ~$1.50/day (t3.small + 2× t3.micro) | ~$6–7/day (EKS fee + t3.large nodes + NAT) |

---

## Prerequisites

Install these tools locally before starting:

- **terraform >= 1.5** — `terraform version`
- **kubectl** — `kubectl version --client`
- **helm >= 3** — `helm version`
- **aws CLI v2** — `aws --version`, configured with `aws configure`
- **eksctl** (optional) — useful for debugging; not required by this runbook

The S3 bucket `gaurav-devops-tfstate` and DynamoDB table `terraform-lock` must exist
(shared with the kubeadm stack — if you've run that runbook they already do).

---

## Step-by-step

### 1. Provision the EKS cluster (Terraform)

```sh
cd terraform-eks
terraform init
terraform plan          # review: VPC, EKS cluster, 2 IRSA roles
terraform apply         # ~12–15 min; EKS control plane takes time
terraform output        # note lb_controller_role_arn and vpc_id
```

This creates:
- A VPC (10.10.0.0/16) with public + private subnets across 2 AZs
- An EKS managed control plane (Kubernetes 1.30)
- A managed node group (2× t3.large in private subnets)
- EKS managed addons: coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver
- Two IRSA roles: EBS CSI driver + AWS Load Balancer Controller

> State is stored at `s3://gaurav-devops-tfstate/eks/terraform.tfstate` — separate
> from the kubeadm stack (`online-boutique/terraform.tfstate`).

### 2. Configure kubectl

```sh
aws eks update-kubeconfig --region ap-south-1 --name online-boutique-eks
# or use the output directly:
$(cd terraform-eks && terraform output -raw update_kubeconfig_command)

kubectl get nodes        # should show 2 nodes in Ready state
```

### 3. Install cluster add-ons

```sh
export LB_ROLE_ARN=$(cd terraform-eks && terraform output -raw lb_controller_role_arn)
export VPC_ID=$(cd terraform-eks && terraform output -raw vpc_id)
bash scripts/eks-addons.sh
```

This installs:
- The `aws-load-balancer-controller` ServiceAccount (annotated with IRSA ARN)
- AWS Load Balancer Controller via Helm (reads Ingress → provisions real ALBs)

The EBS CSI driver is already running (EKS managed addon from Step 1).

### 4. Deploy the application

```sh
kubectl apply -k kustomize/overlays/eks
kubectl wait -n boutique --for=condition=ready pod --all --timeout=300s
```

This applies: namespace, gp3 StorageClass, 14 microservices, MySQL for reviews,
PodDisruptionBudgets, and the ALB Ingress.

### 5. Get the ALB DNS (the app URL)

```sh
kubectl get ingress -n boutique
```

The `ADDRESS` column shows the ALB DNS name — it takes ~2 minutes to provision
after the Ingress is created. Open `http://<ALB_DNS>` in a browser.

> The ALB DNS is generated by AWS and changes if the Ingress is deleted and
> recreated. For a stable URL, create a Route 53 CNAME pointing to the ALB DNS.

### 6. (Optional) Register with ArgoCD

If ArgoCD is installed on the EKS cluster (`scripts/setup-argocd.sh`), register
the EKS Application for GitOps:

```sh
kubectl apply -f argocd/apps/eks.yaml
kubectl -n argocd get applications   # vanta-boutique-eks shows OutOfSync → Sync manually
```

The EKS ArgoCD app defaults to **manual sync** (unlike staging which is auto).
Sync deliberately in the ArgoCD UI or:
```sh
# If argocd CLI is installed:
argocd app sync vanta-boutique-eks
```

---

## Teardown (stop the bill)

```sh
# 1. Remove the app (frees EBS volumes and the ALB)
kubectl delete -k kustomize/overlays/eks

# 2. Destroy all AWS infrastructure
cd terraform-eks
terraform destroy -auto-approve
# ~10–12 min; destroys EKS cluster, node group, NAT gateway, VPC
```

> If `terraform destroy` fails on the VPC (ENIs still attached), wait 5 minutes
> for the ALB to fully de-provision, then retry. The EBS CSI driver creates EBS
> volumes from PVCs — they are retained (reclaimPolicy: Retain) on purpose.
> Delete them manually from the EC2 console after confirming the data is not needed.

---

## Troubleshooting

**ALB not provisioning (Ingress ADDRESS stays blank)**
- Check the LB controller logs: `kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller`
- Verify public subnets have tag `kubernetes.io/role/elb=1` (set by Terraform)
- Verify the IRSA annotation on the `aws-load-balancer-controller` ServiceAccount

**MySQL PVC stays Pending**
- Check the StorageClass: `kubectl get sc` — `gp3` should be default
- Check EBS CSI pods: `kubectl -n kube-system get pods -l app=ebs-csi-controller`
- The PVC uses `WaitForFirstConsumer` — it only binds once a pod is scheduled

**Pods stuck due to max-pods limit**
- VPC CNI limits pods-per-node to ENI slots: t3.large supports up to 35 pods
- With 2 nodes = 70 pod slots for 14 services × 2 replicas = 28 pods (fine)
- If you add more services/replicas, scale the node group first

**kubectl "Unauthorized" after cluster recreate**
- Run `aws eks update-kubeconfig` again — the old kubeconfig entry points to the old endpoint
