# =============================================================================
# Terraform Remote State — S3 + DynamoDB Locking
# =============================================================================
# WHY: Local terraform.tfstate is a single point of failure.
#      If your laptop crashes or another engineer runs terraform apply,
#      the infrastructure state can be corrupted or destroyed.
#
# PREREQUISITES (run once before 'terraform init -migrate-state'):
#   aws s3api create-bucket --bucket gaurav-devops-tfstate --region ap-south-1 \
#     --create-bucket-configuration LocationConstraint=ap-south-1
#   aws s3api put-bucket-versioning --bucket gaurav-devops-tfstate \
#     --versioning-configuration Status=Enabled
#   aws dynamodb create-table --table-name terraform-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region ap-south-1
# =============================================================================
terraform {
  backend "s3" {
    bucket         = "gaurav-devops-tfstate"
    key            = "online-boutique/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}
