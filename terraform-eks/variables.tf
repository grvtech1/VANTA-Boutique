# =============================================================================
# VARIABLES — Parameterize everything (never hardcode!)
# =============================================================================
# WHY variables?
#   Change region/size/version without touching main logic.
#   Different tfvars files can target dev vs prod EKS clusters.
# =============================================================================

variable "aws_region" {
  description = "AWS region — Mumbai, same as the kubeadm stack"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Used as a prefix for all related resources."
  type        = string
  default     = "online-boutique-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version managed by EKS. Patch is handled by EKS; only track minor versions here."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EC2 instance type for managed node group workers. m7i-flex.large = 2 vCPU / 8 GiB, and it is on the Free Plan eligible list (t3.large is not)."
  type        = string
  default     = "m7i-flex.large"
}

variable "node_desired" {
  description = "Desired number of worker nodes. EKS will try to maintain this count."
  type        = number
  default     = 2
}

variable "node_min" {
  description = "Minimum nodes the cluster autoscaler will never go below."
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Maximum nodes the cluster autoscaler can scale up to during peak load."
  type        = number
  default     = 3
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the EKS VPC.
    DELIBERATELY different from the kubeadm VPC (10.0.0.0/16) to allow future
    VPC peering without overlapping addresses — a common production pattern
    when you need dev (kubeadm) to talk to staging (EKS).
  EOT
  type        = string
  default     = "10.10.0.0/16"
}
