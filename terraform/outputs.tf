# =============================================================================
# OUTPUTS — Display useful information after terraform apply
# =============================================================================
# These are like "return values" — Terraform shows them after creating resources
# =============================================================================

# --- Master Node Access ---
output "master_elastic_ip" {
  description = "⭐ PERMANENT public IP of K8s master (survives stop/start!)"
  value       = aws_eip.master_eip.public_ip
}

output "master_private_ip" {
  description = "Private IP of K8s master node"
  value       = aws_instance.k8s_master.private_ip
}

# --- Worker Node Access ---
output "worker_public_ips" {
  description = "Public IPs of K8s worker nodes (dynamic — change on restart)"
  value       = aws_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of K8s worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

# --- Quick Commands ---
output "ssh_command_master" {
  description = "SSH command to connect to master (uses permanent EIP)"
  value       = "ssh -i terraform/k8s-key.pem ubuntu@${aws_eip.master_eip.public_ip}"
}

output "ssh_command_worker_1" {
  description = "SSH command to connect to worker 1"
  value       = "ssh -i terraform/k8s-key.pem ubuntu@${aws_instance.k8s_workers[0].public_ip}"
}

output "ssh_command_worker_2" {
  description = "SSH command to connect to worker 2"
  value       = "ssh -i terraform/k8s-key.pem ubuntu@${aws_instance.k8s_workers[1].public_ip}"
}

output "kubeadm_init_command" {
  description = "🔧 kubeadm init command with EIP in SANs (run on master via SSH)"
  value       = "sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=10.0.1.10 --apiserver-cert-extra-sans=${aws_eip.master_eip.public_ip}"
}

output "destroy_command" {
  description = "⚠️ Run this to DESTROY all resources and stop billing!"
  value       = "cd ~/online-boutique/terraform && terraform destroy -auto-approve"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.k8s_vpc.id
}
