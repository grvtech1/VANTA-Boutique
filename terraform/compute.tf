# =============================================================================
# EC2 INSTANCES — Your Kubernetes Servers
# =============================================================================
# Architecture:
#   Master (t3.medium) — Runs K8s control plane (API server, etcd, scheduler)
#   Worker-1 (t3.medium) — Runs your application pods
#   Worker-2 (t3.medium) — Runs your application pods (HA)
#
# AMI: Ubuntu 22.04 LTS — Most common OS for K8s in production
# =============================================================================

# --- Find the latest Ubuntu 22.04 AMI ---
# This automatically finds the newest Ubuntu image (no hardcoding AMI IDs!)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical (Ubuntu's company)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# User Data Script — Runs automatically when instance boots
# =============================================================================
# This script installs Docker + kubeadm + kubelet + kubectl on EVERY node
# It's the "Ansible-lite" approach — bootstrap comes from Terraform,
# then Ansible handles the K8s cluster setup
# =============================================================================

locals {
  common_user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    # ─── Disable swap (K8s requirement) ───
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # ─── Load kernel modules for K8s networking ───
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF
    modprobe overlay
    modprobe br_netfilter

    # ─── Set sysctl params (persist across reboots) ───
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF
    sysctl --system

    # ─── Install containerd (container runtime) ───
    apt-get update -qq
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg

    # Docker's official GPG key + repo
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq containerd.io

    # Configure containerd to use systemd cgroup driver
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd

    # ─── Install kubeadm, kubelet, kubectl ───
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    systemctl enable kubelet

    echo "=== K8s prerequisites installed successfully ==="
  USERDATA

  # Master-specific: includes swap to prevent OOM on t3.small (2GB RAM)
  master_user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    # ─── Setup 2GB swap FIRST (before K8s) ───
    # t3.small has only 2GB RAM. Control plane + ArgoCD + monitoring = ~3.5GB
    # Swap prevents OOM-killer from freezing the node
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # Low swappiness = only swap under pressure (production-safe)
    echo 'vm.swappiness=10' >> /etc/sysctl.d/99-swap.conf

    # ─── Configure kubelet to allow swap ───
    # Write to /etc/default/kubelet which is natively imported by kubeadm's systemd drop-in
    echo 'KUBELET_EXTRA_ARGS="--fail-swap-on=false"' > /etc/default/kubelet


    # ─── Load kernel modules for K8s networking ───
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF
    modprobe overlay
    modprobe br_netfilter

    # ─── Set sysctl params (persist across reboots) ───
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF
    sysctl --system

    # ─── Install containerd (container runtime) ───
    apt-get update -qq
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg

    # Docker's official GPG key + repo
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq containerd.io

    # Configure containerd to use systemd cgroup driver
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd

    # ─── Install kubeadm, kubelet, kubectl ───
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    systemctl daemon-reload
    systemctl enable kubelet

    echo "=== Master node ready (2GB swap + K8s prerequisites) ==="
  USERDATA
}

# =============================================================================
# MASTER NODE — The brain of your K8s cluster
# =============================================================================
resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = aws_key_pair.k8s_key.key_name
  subnet_id              = aws_subnet.k8s_public.id
  vpc_security_group_ids = [aws_security_group.k8s_master_sg.id]
  private_ip             = "10.0.1.10"

  # Master gets its own user_data with swap pre-configured
  # This prevents OOM freezes on t3.small (2GB RAM) when running
  # control plane + ArgoCD + monitoring simultaneously
  user_data = local.master_user_data

  root_block_device {
    volume_size = 20    # 20 GB disk (free tier: 30GB total)
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-master"
    Role = "master"
  }
}

# =============================================================================
# WORKER NODES — Where your application pods run
# =============================================================================
resource "aws_instance" "k8s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.k8s_key.key_name
  subnet_id              = aws_subnet.k8s_public.id
  vpc_security_group_ids = [aws_security_group.k8s_worker_sg.id]
  private_ip             = "10.0.1.${11 + count.index}"

  user_data = local.common_user_data

  root_block_device {
    volume_size = 20    # 20 GB disk (free tier)
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  }
}
