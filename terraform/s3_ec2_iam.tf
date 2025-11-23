# =============================================================================
# S3 Buckets for MongoDB backups (intentionally public for exercise)
# =============================================================================

resource "aws_s3_bucket" "mongo_backups" {
  bucket        = coalesce(var.backup_bucket_name, "${var.project}-mongo-backups-${random_id.bucket_suffix.hex}")
  force_destroy = true

  tags = {
    Name    = "${var.project}-mongo-backups"
    Purpose = "MongoDB database backups (intentionally public)"
  }
}

# Separate ACL resource (AWS provider v4+ requirement)
resource "aws_s3_bucket_acl" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id
  acl    = "public-read"
}

# Disable block public access (intentionally insecure for exercise)
resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Versioning
resource "aws_s3_bucket_versioning" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rule
resource "aws_s3_bucket_lifecycle_configuration" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  rule {
    id     = "cleanup-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# S3 bucket for application backups (referenced in outputs)
resource "aws_s3_bucket" "app_backup" {
  bucket        = "${var.project}-app-backup-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project}-app-backup"
    Purpose = "Application backup storage"
  }
}

# IAM role for EC2 instance (intentionally permissive for exercise)
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Security group for Mongo VM (SSH open to world intentionally)
resource "aws_security_group" "mongo_sg" {
  name        = "${var.project}-mongo-sg"
  description = "Allow SSH + Mongo from cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # intentionally open for the exercise
  }

  # Allow MongoDB port from the VPC's private subnets CIDR
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance for Mongo
resource "aws_instance" "mongo_vm" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.public_subnets[0]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.mongo_sg.id]

  # Use templatefile to inject variables into user-data
  user_data = templatefile("${path.module}/user-data-mongo.tpl", {
    backup_bucket = aws_s3_bucket.mongo_backups.bucket
    secret_name   = data.aws_secretsmanager_secret.mongodb_credentials.name
    aws_region    = var.aws_region
  })

  tags = {
    Name = "${var.project}-mongo-vm"
  }
}

# AMI data
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
