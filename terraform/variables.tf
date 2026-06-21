# =============================================================================
# VARIABLES — Parameterize everything (never hardcode!)
# =============================================================================
# WHY variables?
#   - Change region/size without editing main code
#   - Different values for dev/staging/prod
#   - Reusable across teams
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy in (Mumbai = closest to India)"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "online-boutique"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (10.0.0.0/16 = 65,536 IPs)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for public subnet (internet-accessible)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "master_instance_type" {
  description = "EC2 instance type for K8s master (t3.small = 2 CPU, 2GB RAM + 2GB swap = stable for control plane + monitoring)"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for K8s workers (t3.micro = FREE tier in ap-south-1, 2 CPU, 1GB)"
  type        = string
  default     = "t3.micro"
}

variable "worker_count" {
  description = "Number of K8s worker nodes"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "Name for the SSH key pair"
  type        = string
  default     = "k8s-key"
}
