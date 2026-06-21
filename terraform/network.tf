# =============================================================================
# NETWORKING — VPC, Subnet, Internet Gateway, Route Table
# =============================================================================
# Architecture:
#
#   Internet
#      │
#   ┌──▼──────────────┐
#   │  Internet Gateway │  ← Connects VPC to the internet
#   └──┬──────────────┘
#      │
#   ┌──▼──────────────────────────────────────────┐
#   │  VPC (10.0.0.0/16)                           │
#   │                                              │
#   │  ┌─────────────────────────────────────────┐ │
#   │  │  Public Subnet (10.0.1.0/24)             │ │
#   │  │                                          │ │
#   │  │  Master Node    Worker-1    Worker-2     │ │
#   │  │  10.0.1.10      10.0.1.11   10.0.1.12   │ │
#   │  └─────────────────────────────────────────┘ │
#   └──────────────────────────────────────────────┘
#
# WHY public subnet (not private)?
#   - For learning: simpler setup, direct SSH access
#   - Production: use private subnets + bastion host
# =============================================================================

# --- VPC ---
# A VPC is your own private network inside AWS
# Think of it as your own data center in the cloud
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Allows instances to have DNS names
  enable_dns_support   = true  # Enables DNS resolution inside VPC

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# --- Internet Gateway ---
# Without this, your VPC has NO internet access
# It's the "front door" connecting your VPC to the internet
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --- Public Subnet ---
# A subnet is a smaller network INSIDE your VPC
# "Public" means instances here CAN reach the internet
resource "aws_subnet" "k8s_public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true  # Auto-assign public IPs

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# --- Route Table ---
# Routes tell traffic WHERE to go
# This says: "To reach the internet (0.0.0.0/0), go through the Internet Gateway"
resource "aws_route_table" "k8s_public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# --- Associate Route Table with Subnet ---
# Links the route table to our subnet (without this, subnet has no routes!)
resource "aws_route_table_association" "k8s_public_rta" {
  subnet_id      = aws_subnet.k8s_public.id
  route_table_id = aws_route_table.k8s_public_rt.id
}
