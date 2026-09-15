# =============================================================================
# OUTPUTS — Display useful information after terraform apply
# =============================================================================
# These are "return values" from the Terraform run.
# They're also queryable: terraform output -raw update_kubeconfig_command
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name — used by kubectl, helm, and the eks-addons script"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region the cluster was provisioned in"
  value       = var.aws_region
}

# =============================================================================
# The single most important output after apply — run this to wire kubectl.
# WHY: EKS doesn't drop a kubeconfig file locally like kubeadm does. The aws
# CLI merges the EKS entry into ~/.kube/config for you when you run this.
# =============================================================================
output "update_kubeconfig_command" {
  description = "Run this immediately after terraform apply to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "lb_controller_role_arn" {
  description = <<-EOT
    IAM role ARN for the AWS Load Balancer Controller.
    Pass this as LB_ROLE_ARN when running scripts/eks-addons.sh:
      LB_ROLE_ARN=$(terraform output -raw lb_controller_role_arn) scripts/eks-addons.sh
  EOT
  value = module.irsa_lb_controller.iam_role_arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for the EBS CSI driver (already wired into the cluster_addons block — shown for reference)"
  value       = module.irsa_ebs_csi.iam_role_arn
}

output "vpc_id" {
  description = <<-EOT
    VPC ID — needed by the AWS Load Balancer Controller so it knows which VPC
    to place ALBs in. Pass as VPC_ID when running scripts/eks-addons.sh:
      VPC_ID=$(terraform output -raw vpc_id) scripts/eks-addons.sh
  EOT
  value = module.vpc.vpc_id
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — for reference; kubectl uses this automatically after update-kubeconfig"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — used to create additional IRSA roles for other controllers"
  value       = module.eks.oidc_provider_arn
}

# =============================================================================
# COST CONTROL — the destroy command is the most important thing to remember
# EKS control plane: $0.10/hr | nodes: ~$0.14/hr (2× t3.large) | NAT: ~$0.045/hr
# A forgotten cluster costs ~$6-7/day. Destroy it when done!
# =============================================================================
output "destroy_command" {
  description = "COST CONTROL: Run this to destroy all EKS resources and stop billing"
  value       = "cd ~/VANTA-Boutique/terraform-eks && terraform destroy -auto-approve"
}
