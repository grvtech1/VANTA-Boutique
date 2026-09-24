# =============================================================================
# Terraform + Provider Requirements — EKS Stack
# =============================================================================
# WHY separate from ../terraform?
#   That stack provisions the SELF-MANAGED kubeadm cluster (EC2 nodes, you own
#   the control plane). THIS stack provisions MANAGED EKS — AWS runs etcd,
#   kube-apiserver, kube-controller-manager across 3 AZs for you. Two valid
#   targets; one repo. Never run both stacks simultaneously against the same
#   state key or you will corrupt state.
#
# PREREQUISITE — the S3 bucket + DynamoDB table already exist (created once,
#   shared with the kubeadm stack). If they don't:
#     aws s3api create-bucket --bucket gaurav-devops-tfstate --region ap-south-1 \
#       --create-bucket-configuration LocationConstraint=ap-south-1
#     aws s3api put-bucket-versioning --bucket gaurav-devops-tfstate \
#       --versioning-configuration Status=Enabled
#     aws dynamodb create-table --table-name terraform-lock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST --region ap-south-1
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ==========================================================================
  # Remote state — separate key from the kubeadm stack so they never collide.
  # "eks/terraform.tfstate" lives alongside "online-boutique/terraform.tfstate"
  # in the SAME bucket, versioned independently.
  # ==========================================================================
  backend "s3" {
    bucket         = "gaurav-devops-tfstate"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

# =============================================================================
# PROVIDER — same Mumbai region as the kubeadm stack; tags every resource
# so Cost Explorer can separate EKS spend from kubeadm spend.
# =============================================================================
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "online-boutique"
      Environment = "eks"
      ManagedBy   = "terraform"
      Owner       = "gaurav"
      Stack       = "eks-managed" # distinguishes from the kubeadm stack
    }
  }
}
