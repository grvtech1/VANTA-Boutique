# =============================================================================
# ELASTIC IP — Static public IP for master node
# =============================================================================
# WHY Elastic IP?
#   PROBLEM: Every time you stop/start EC2, AWS assigns a NEW random public IP.
#            kubeadm bakes the IP into the API server's TLS certificate (SANs).
#            New IP = certificate mismatch = kubectl refuses to connect.
#            We had to run fix-tls-cert.sh EVERY session.
#
#   SOLUTION: Elastic IP gives you a PERMANENT public IP that survives reboots.
#            kubeadm init includes this EIP in SANs → cert never breaks.
#
#   COST: $0/hr when attached to a RUNNING instance
#         $0.005/hr when instance is STOPPED (~$3.60/month if left stopped)
#         → Always destroy when done, never leave stopped!
# =============================================================================

resource "aws_eip" "master_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-master-eip"
    Role = "master"
  }
}

# --- Associate EIP with Master Instance ---
# WHY separate resource?
#   - Terraform creates EIP first, THEN attaches it
#   - If instance is recreated, EIP stays allocated and re-attaches
#   - Cleaner than putting eip inside aws_instance
resource "aws_eip_association" "master_eip_assoc" {
  instance_id   = aws_instance.k8s_master.id
  allocation_id = aws_eip.master_eip.id
}
