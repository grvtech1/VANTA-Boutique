# =============================================================================
# Terraform Configuration for Self-Managed Kubernetes on AWS
# =============================================================================
# WHAT:  Creates VPC + 3 EC2 instances (1 master, 2 workers) for K8s
# WHY:   Learn real infrastructure — no managed services, YOU control everything
# COST:  ~$1.5/day when running, $0 when destroyed
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# =============================================================================
# PROVIDER — Tells Terraform "talk to AWS in Mumbai region"
# =============================================================================
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "online-boutique"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "gaurav"
    }
  }
}
