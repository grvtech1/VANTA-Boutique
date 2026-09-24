# =============================================================================
# EKS Managed Cluster — Terraform
# =============================================================================
# WHAT:  Provisions a production-grade managed EKS control plane + managed
#        node group on AWS, inside a purpose-built VPC with public/private
#        subnets across 2 AZs.
#
# WHY "managed" vs the kubeadm stack?
#   ../terraform  → kubeadm = YOU own everything (control plane, etcd, upgrades,
#                   HA setup). Great for learning the internals.
#   THIS stack    → EKS = AWS owns the control plane. It runs across 3 AZs,
#                   auto-patches, auto-scales, and never shows you an etcd node.
#                   You pay $0.10/hr for that guarantee. Use in production or
#                   when you want to focus on the app, not k8s plumbing.
#
# COST:  ~$0.10/hr (EKS control plane) + nodes (~$0.07/hr per t3.large)
#        + NAT gateway (~$0.045/hr) + ALB (pay-per-request). Always destroy!
#
# MODULE VERSIONS (pinned for reproducibility):
#   VPC  : terraform-aws-modules/vpc/aws  5.x
#   EKS  : terraform-aws-modules/eks/aws  20.x  (v20 API — see inline notes)
#   IAM  : terraform-aws-modules/iam/aws  5.x
# =============================================================================

# =============================================================================
# 1. VPC — Private/public subnets across 2 AZs
# =============================================================================
# WHY 2 AZs and not 3?
#   3 AZs = more fault tolerance but also 3 NAT gateways if we used one-per-AZ.
#   single_nat_gateway=true reduces cost significantly for a lab cluster.
#   In real prod you'd use one NAT per AZ for full HA.
#
# WHY private subnets for nodes?
#   Nodes should NOT have public IPs. Only the load balancer (ALB) lives in
#   public subnets. Nodes talk to the internet through the single NAT gateway.
#
# WHY the subnet tags?
#   AWS Load Balancer Controller discovers subnets by these tags:
#     public  → kubernetes.io/role/elb=1         (internet-facing ALBs)
#     private → kubernetes.io/role/internal-elb=1 (internal ALBs)
#   Without them the LB controller cannot place load balancers. This is a very
#   common "why isn't my ALB provisioning?" gotcha.
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # 2 AZs in Mumbai: ap-south-1a and ap-south-1b
  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24"]

  # Single NAT gateway — costs ~$0.045/hr but saves two NAT instances.
  # Trade-off: if ap-south-1a loses its NAT, nodes in ap-south-1b also lose
  # internet egress until the NAT fails over. Acceptable for a lab.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true # required: EKS nodes register via DNS
  enable_dns_support   = true

  # Tags required by AWS Load Balancer Controller — see WHY above.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# =============================================================================
# 2. IRSA — EBS CSI Driver (persistent volumes → EBS gp3)
# =============================================================================
# WHY IRSA (IAM Roles for Service Accounts)?
#   The old way: give EC2 nodes an instance profile with S3/EBS/etc permissions.
#   Problem: EVERY pod on that node inherits those permissions — blast radius huge.
#
#   IRSA: a specific Kubernetes ServiceAccount gets a specific IAM role via OIDC
#   federation. Only pods that mount that SA inherit the permissions. Principle
#   of least privilege at the pod level — a crucial interview differentiator.
#
# This role is for the ebs-csi-controller-sa ServiceAccount that the aws-ebs-csi-
# driver addon creates. It needs ec2:CreateVolume, ec2:AttachVolume, etc., which
# attach_ebs_csi_policy wires up from the AWS-managed policy.
# =============================================================================
module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true # attaches AmazonEBSCSIDriverPolicy

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# =============================================================================
# 3. IRSA — AWS Load Balancer Controller
# =============================================================================
# WHY AWS LB Controller and not the legacy in-tree cloud provider LB?
#   The in-tree provider only creates classic ELBs (NLBs for Services type=LB).
#   AWS LB Controller creates modern ALBs from Ingress resources — path routing,
#   WAF integration, target-type=ip (direct pod routing, no kube-proxy hop).
#   It is the ONLY supported way to create ALBs from Kubernetes on EKS.
#
# This role is for the aws-load-balancer-controller ServiceAccount that
# scripts/eks-addons.sh creates. It needs ec2:Describe*, elbv2:*, etc.
# =============================================================================
module "irsa_lb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true # attaches AWSLoadBalancerControllerIAMPolicy

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# =============================================================================
# 4. EKS Cluster — Managed control plane + managed node group
# =============================================================================
# MODULE API NOTE (v20 vs v19 breaking change):
#   v20 removed the legacy "aws_auth" ConfigMap approach. Authentication now uses
#   EKS Access Entries (IAM-native). enable_cluster_creator_admin_permissions=true
#   automatically grants the Terraform caller cluster-admin via an Access Entry —
#   you don't need to manually edit aws-auth anymore.
#
# WHY cluster_endpoint_public_access=true?
#   Lets you run kubectl from your laptop without a VPN. For real prod you'd set
#   cluster_endpoint_public_access_cidrs to your office/VPN IP ranges. We keep
#   it fully open here for lab convenience — never do this for customer workloads.
#
# WHY cluster_addons?
#   EKS-managed addons are patched by AWS (security fixes, k8s version compat).
#   Without them you'd pin and maintain the YAML yourself. Four essential addons:
#     coredns       — DNS resolution inside the cluster
#     kube-proxy    — iptables rules for Service ClusterIP
#     vpc-cni       — AWS VPC CNI (pods get VPC-native IPs, no overlay network)
#     aws-ebs-csi-driver — CSI driver for EBS persistent volumes (PVCs → gp3)
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Allow kubectl from your laptop (restrict to your IP in real prod)
  cluster_endpoint_public_access = true

  # v20 API: grant the caller (your IAM identity) cluster-admin via EKS Access Entry.
  # Without this you'd need to separately edit aws-auth ConfigMap.
  enable_cluster_creator_admin_permissions = true

  # Audit and compliance logging to CloudWatch
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Enforce standard support to prevent the 6x ($0.60/hr) extended support charge
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # control-plane ENIs land in private subnets

  # ------------------------------------------------------------------
  # Managed EKS add-ons
  # ------------------------------------------------------------------
  cluster_addons = {
    coredns = {
      most_recent = true
      # coredns can be installed after nodes are ready (it needs compute to schedule)
    }
    # before_compute=true: install kube-proxy BEFORE the managed node group comes up.
    # WHY: nodes need kube-proxy's iptables rules to route Service ClusterIP traffic
    # before they can join the cluster and pass health checks. Without this, nodes
    # may fail readiness briefly on first join.
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    # before_compute=true: vpc-cni MUST be installed before any node joins the cluster.
    # WHY: VPC CNI is the network plugin. Nodes without it cannot allocate pod IPs
    # and will remain NotReady. Installing it before_compute avoids that bootstrap race.
    vpc-cni = {
      most_recent    = true
      before_compute = true
      # Prefix delegation: each ENI slot gets a /28 (16 IPs) instead of one IP,
      # so a node can run far more pods before IP exhaustion. Set on day one —
      # changing it later means rolling every node.
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    # EBS CSI driver — needed so PVCs (MySQL for reviews) bind to EBS volumes.
    # IRSA role wired here so the controller pods can call ec2:CreateVolume, etc.
    # No before_compute needed — storage runs fine once the cluster is up.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  # ------------------------------------------------------------------
  # Managed node group — EKS launches and manages the EC2 worker nodes.
  # "managed" means EKS drains nodes before replacing them on updates.
  # ------------------------------------------------------------------
  eks_managed_node_groups = {
    # One group is enough for a lab. In prod add a separate group per AZ
    # or per workload class (cpu vs memory optimised).
    main = {
      name           = "${var.cluster_name}-main-ng"
      instance_types = [var.node_instance_type] # m7i-flex.large default

      # Kubernetes 1.33+ has no Amazon Linux 2 AMIs; module v20 still defaults
      # to AL2, so without this line the node group fails to create.
      ami_type = "AL2023_x86_64_STANDARD"

      # The module builds the node IAM role as "<name>-eks-node-group-" as a
      # name_prefix, which blows past the 38-char limit for this cluster name.
      # A fixed, short role name avoids it.
      iam_role_use_name_prefix = false
      iam_role_name            = "${var.cluster_name}-node"

      # IMDSv2 only, hop limit 1: a pod is one network hop away from the node,
      # so it cannot reach instance metadata and borrow the node's IAM role.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      desired_size = var.node_desired # 2
      min_size     = var.node_min     # 2
      max_size     = var.node_max     # 3

      # Nodes land in private subnets — no direct internet access.
      # They egress through the single NAT gateway.
      subnet_ids = module.vpc.private_subnets

      # EBS root volume for the node OS — gp3 is cheaper and faster than gp2.
      disk_size = 30 # GiB

      # Nodes don't need direct public IPs — traffic routes through the NAT.
      associate_public_ip_address = false
    }
  }
}

# =============================================================================
# 5. IRSA — External Secrets Operator (SSM Parameter Store → Kubernetes Secret)
# =============================================================================
# WHY: app secrets (the reviews MySQL passwords) should live in SSM Parameter
# Store, not in Git. ESO runs in-cluster, reads the parameters with this role,
# and writes a normal Kubernetes Secret the pods already consume.
#
# WHY Parameter Store and not Secrets Manager: the standard tier is free;
# Secrets Manager is $0.40 per secret per month and only earns that when you
# need managed rotation.
#
# Least privilege: read-only, and only under the /vanta/ prefix. SecureString
# values use the AWS managed aws/ssm key, whose key policy already allows
# decryption through SSM for principals in this account.
# =============================================================================
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "eso_ssm_read" {
  name        = "${var.cluster_name}-eso-ssm-read"
  description = "External Secrets Operator: read SSM parameters under /vanta/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/vanta/*"
    }]
  })
}

module "irsa_eso" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name        = "${var.cluster_name}-eso"
  role_policy_arns = { ssm_read = aws_iam_policy.eso_ssm_read.arn }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}
