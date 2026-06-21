# =============================================================================
# SECURITY GROUPS — Firewall rules for your servers
# =============================================================================
# Security Groups = AWS firewall
# "Allow traffic on port X from source Y"
#
# K8s needs these ports open:
#   Master: 6443 (API), 2379-2380 (etcd), 10250-10252 (kubelet)
#   Worker: 10250 (kubelet), 30000-32767 (NodePort services)
#   All:    22 (SSH), ICMP (ping)
#
# CALICO CNI needs:
#   All nodes: 179 (BGP), 4789 (VXLAN fallback), 5473 (Calico Typha)
#
# WHY Calico instead of Flannel?
#   Flannel = basic overlay networking only
#   Calico  = networking + NetworkPolicy enforcement (pod-level firewall)
#   Production clusters use Calico or Cilium, never Flannel
# =============================================================================

# --- Security Group for K8s Master ---
resource "aws_security_group" "k8s_master_sg" {
  name_prefix = "${var.project_name}-master-"
  description = "Security group for K8s master node"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH — Remote access to manage the server
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Production: restrict to your IP only!
  }

  # Kubernetes API Server — How kubectl talks to K8s
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd — K8s database (stores all cluster state)
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # Only from within VPC
  }

  # Kubelet API — Master talks to nodes through this
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico BGP — Pod networking uses BGP protocol
  # WHY BGP? It's the same protocol internet routers use.
  # Calico advertises pod CIDRs between nodes via BGP peering.
  ingress {
    description = "Calico BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico VXLAN — Fallback overlay when BGP is not available
  ingress {
    description = "Calico VXLAN overlay"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico Typha — Health and metrics (optional, for large clusters)
  ingress {
    description = "Calico Typha"
    from_port   = 5473
    to_port     = 5473
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort Services — Access apps from outside (30000-32767)
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from within VPC (pod communication)
  ingress {
    description = "All VPC internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow ALL outbound traffic (servers need internet for updates, Docker pulls)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-master-sg"
    Role = "master"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Security Group for K8s Workers ---
resource "aws_security_group" "k8s_worker_sg" {
  name_prefix = "${var.project_name}-worker-"
  description = "Security group for K8s worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubelet API — Master sends commands to workers through this
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico BGP
  ingress {
    description = "Calico BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico VXLAN
  ingress {
    description = "Calico VXLAN overlay"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort Services — How users access your apps
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from within VPC (pod communication)
  ingress {
    description = "All VPC internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow ALL outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-worker-sg"
    Role = "worker"
  }

  lifecycle {
    create_before_destroy = true
  }
}
