module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.27"

  subnets = module.vpc.private_subnets

  node_groups = {
    default = {
      desired_capacity = var.eks_node_group_desired
      max_capacity     = 3
      min_capacity     = 1

      instance_type = "t3.medium"
    }
  }

  manage_aws_auth = true
}
