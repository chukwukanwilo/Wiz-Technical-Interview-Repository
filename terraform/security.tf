# =============================================================================
# Cloud Native Security Controls
# =============================================================================
# Implements detective controls for the Wiz exercise:
# - CloudTrail: Control plane audit logging
# - AWS Config: Resource compliance monitoring
# - Config Rules: Detect intentional misconfigurations

# -----------------------------------------------------------------------------
# CloudTrail - Audit Logging
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project}-cloudtrail-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "cloudtrail"
    Purpose = "CloudTrail logs"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "${var.project}-cloudtrail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# -----------------------------------------------------------------------------
# AWS Config - Detective Controls
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project}-config-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "config"
    Purpose = "Config logs"
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketPutObject"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "config" {
  name = "${var.project}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${var.project}-config-s3"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.config.arn,
          "${aws_s3_bucket.config.arn}/*"
        ]
      }
    ]
  })
}

# Use existing Config recorder (limit: 1 per region)
data "aws_config_configuration_recorder" "existing" {
  name = "default"
}

# -----------------------------------------------------------------------------
# Config Rules - Detect Misconfigurations
# -----------------------------------------------------------------------------

# Detect public S3 buckets (will flag mongo_backups bucket)
resource "aws_config_config_rule" "s3_public_read" {
  name = "${var.project}-s3-public-read"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [data.aws_config_configuration_recorder.existing]
}

# Detect unrestricted SSH (will flag mongo_sg)
resource "aws_config_config_rule" "restricted_ssh" {
  name = "${var.project}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [data.aws_config_configuration_recorder.existing]
}

# Detect IAM policies with admin access (will flag ec2_role)
resource "aws_config_config_rule" "iam_no_admin" {
  name = "${var.project}-iam-no-admin"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }

  depends_on = [data.aws_config_configuration_recorder.existing]
}

# S3 versioning check
resource "aws_config_config_rule" "s3_versioning" {
  name = "${var.project}-s3-versioning"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
  }

  depends_on = [data.aws_config_configuration_recorder.existing]
}

# -----------------------------------------------------------------------------
# SNS for Alerts (optional)
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "security_alerts" {
  name = "${var.project}-security-alerts"

  tags = {
    Name = "${var.project}-security-alerts"
  }
}

output "security_alerts_topic" {
  description = "SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}
