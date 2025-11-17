# provider & basic infra skeleton (AWS example)
provider "aws" {
  region = var.region
}

# VPC, subnets, EKS cluster, EC2 instance for MongoDB, S3 bucket
# Use modules or community modules for EKS; omitted here for brevity

resource "aws_s3_bucket" "mongo_backups" {
  bucket = var.backup_bucket_name
  acl    = "public-read"
  force_destroy = true
}

# EC2 instance (MongoDB VM) - with a permissive IAM role
resource "aws_iam_role" "mongo_vm_role" {
  name = "mongo_vm_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mongo_attach" {
  role       = aws_iam_role.mongo_vm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # intentionally permissive
}

# outputs: ec2 private ip, s3 bucket name, kubeconfig
