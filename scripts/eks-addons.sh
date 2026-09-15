#!/usr/bin/env bash
# =============================================================================
# eks-addons.sh — Install cluster-level add-ons that Terraform cannot manage.
# =============================================================================
# WHY NOT Terraform?
#   The AWS Load Balancer Controller is a Helm chart, not an EKS managed addon.
#   It needs a pre-existing Kubernetes ServiceAccount annotated with an IRSA
#   role ARN (which Terraform outputs). Terraform has a kubernetes/helm provider
#   but using it creates a chicken-and-egg: the provider needs a live cluster
#   to talk to, but the cluster is created in the same apply. Splitting into a
#   separate script is cleaner and matches the repo's existing pattern
#   (setup-argocd.sh, velero-install.sh).
#
# WHAT this script installs:
#   1. aws-load-balancer-controller ServiceAccount (annotated with IRSA ARN)
#   2. AWS Load Balancer Controller (Helm) — reads Ingress resources + creates ALBs
#
# WHAT this script does NOT install:
#   - EBS CSI driver  — already a managed EKS addon (terraform-eks/main.tf)
#   - gp3 StorageClass — comes from kustomize/overlays/eks/gp3-storageclass.yaml
#   - ArgoCD           — use scripts/setup-argocd.sh as on the kubeadm cluster
#
# PREREQUISITES:
#   - kubectl configured for the EKS cluster (run: aws eks update-kubeconfig ...)
#   - helm >= 3
#   - LB_ROLE_ARN and VPC_ID set (from terraform-eks outputs — see INPUTS below)
#
# USAGE:
#   export LB_ROLE_ARN=$(cd terraform-eks && terraform output -raw lb_controller_role_arn)
#   export VPC_ID=$(cd terraform-eks && terraform output -raw vpc_id)
#   bash scripts/eks-addons.sh
#
# IDEMPOTENT: safe to re-run — kubectl apply and helm upgrade --install are
#   both idempotent operations.
# =============================================================================
set -euo pipefail

# =============================================================================
# INPUTS — override via environment variables
# =============================================================================
CLUSTER_NAME="${CLUSTER_NAME:-online-boutique-eks}"
AWS_REGION="${AWS_REGION:-ap-south-1}"

# Required — must come from terraform-eks outputs. Fail fast if missing.
LB_ROLE_ARN="${LB_ROLE_ARN:?ERROR: set LB_ROLE_ARN from: cd terraform-eks && terraform output -raw lb_controller_role_arn}"
VPC_ID="${VPC_ID:?ERROR: set VPC_ID from: cd terraform-eks && terraform output -raw vpc_id}"

echo "============================================================"
echo " EKS Add-ons installer"
echo "  Cluster : ${CLUSTER_NAME}"
echo "  Region  : ${AWS_REGION}"
echo "  VPC     : ${VPC_ID}"
echo "  LB Role : ${LB_ROLE_ARN}"
echo "============================================================"

# =============================================================================
# STEP 1 — ServiceAccount for the AWS Load Balancer Controller
# =============================================================================
# WHY create the SA before helm install?
#   We set serviceAccount.create=false in the helm values below so the chart
#   does NOT create its own SA (which would lack the IRSA annotation).
#   Instead we create the SA here with the exact annotation the IRSA mechanism
#   requires: eks.amazonaws.com/role-arn points to the IAM role whose trust
#   policy allows the OIDC provider to assume it for THIS namespace + SA name.
#
# The annotation is what connects K8s identity to IAM identity — without it
# the controller pods receive no AWS credentials and cannot call the ELBv2 API.
# =============================================================================
echo
echo "== 1. Create aws-load-balancer-controller ServiceAccount =="
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: "${LB_ROLE_ARN}"
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
EOF

echo "ServiceAccount created/updated."

# =============================================================================
# STEP 2 — Helm: AWS Load Balancer Controller
# =============================================================================
# WHY helm upgrade --install and not helm install?
#   --install creates if absent, upgrade if present → idempotent.
#
# WHY serviceAccount.create=false?
#   We already created the SA with the IRSA annotation above.
#   Letting Helm create it would overwrite our annotation with an unannotated SA.
#
# WHY pass clusterName, region, vpcId?
#   The controller uses these to make ELBv2/EC2 API calls scoped to our cluster.
#   Without vpcId it would have to describe all VPCs — slower and noisier.
# =============================================================================
echo
echo "== 2. Add EKS Helm repo and install AWS Load Balancer Controller =="
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}"

echo "AWS Load Balancer Controller installed/updated."
echo
echo "Waiting for controller deployment to be ready..."
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s

# =============================================================================
# STEP 3 — Notes on what Terraform already handled
# =============================================================================
echo
echo "============================================================"
echo " NOTE: already handled by terraform-eks/main.tf:"
echo "   - EBS CSI driver (aws-ebs-csi-driver EKS managed addon)"
echo "   - IRSA role for EBS CSI (module.irsa_ebs_csi)"
echo "   - IRSA role for LB Controller (module.irsa_lb_controller)"
echo
echo " The gp3 StorageClass is applied with the overlay:"
echo "   kubectl apply -k kustomize/overlays/eks"
echo "============================================================"

# =============================================================================
# NEXT STEPS
# =============================================================================
echo
echo "============================================================"
echo " NEXT STEPS"
echo "============================================================"
echo
echo " 1. Deploy the application:"
echo "    kubectl apply -k kustomize/overlays/eks"
echo
echo " 2. Wait for pods:"
echo "    kubectl wait -n boutique --for=condition=ready pod --all --timeout=300s"
echo
echo " 3. Get the ALB DNS name (takes ~2 min to provision after apply):"
echo "    kubectl get ingress -n boutique"
echo "    # ADDRESS column = ALB DNS e.g. k8s-boutique-xxxx.ap-south-1.elb.amazonaws.com"
echo
echo " 4. Open in browser: http://<ALB_DNS>"
echo
echo " TEARDOWN (STOP BILLING):"
echo "    kubectl delete -k kustomize/overlays/eks"
echo "    cd terraform-eks && terraform destroy -auto-approve"
echo "============================================================"
