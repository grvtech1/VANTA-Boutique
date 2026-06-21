# =============================================================================
# SSH KEY PAIR — How you'll log into your servers
# =============================================================================
# Terraform generates a key pair:
#   - Private key → saved locally (YOU use this to SSH in)
#   - Public key  → uploaded to AWS (servers use this to verify you)
# =============================================================================

# Generate SSH key pair
resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload public key to AWS
resource "aws_key_pair" "k8s_key" {
  key_name   = var.key_name
  public_key = tls_private_key.k8s_key.public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Save private key locally for SSH access
resource "local_file" "k8s_private_key" {
  content         = tls_private_key.k8s_key.private_key_pem
  filename        = "${path.module}/k8s-key.pem"
  file_permission = "0400"  # Read-only by owner (SSH requires this!)
}
