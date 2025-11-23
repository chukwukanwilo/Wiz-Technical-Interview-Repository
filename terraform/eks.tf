module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable control plane logging (required for CloudTrail/security demo)
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Managed Node Group in private subnets
  eks_managed_node_groups = {
    default = {
      name           = "${var.project}-node-group"
      desired_size   = var.eks_node_group_desired
      max_size       = 3
      min_size       = 1
      instance_types = ["t3.medium"]

      # Ensure nodes are in private subnets
      subnet_ids = module.vpc.private_subnets
    }
  }

  # Use Access Entries API (aws-auth ConfigMap is deprecated)
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  tags = {
    Name        = "${var.project}-eks"
    Environment = "wiz-exercise"
  }
}
