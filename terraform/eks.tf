module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable public endpoint access for kubectl/CI
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable control plane logging (required for CloudTrail/security demo)
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Managed Node Group in private subnets
  eks_managed_node_groups = {
    default = {
      name           = "${var.project}-ng"
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
  
  # Grant access to local IAM user
  access_entries = {
    local_admin = {
      principal_arn = "arn:aws:iam::253490792199:user/odl_user_1962304"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Name        = "${var.project}-eks"
    Environment = "wiz-exercise"
  }
}
