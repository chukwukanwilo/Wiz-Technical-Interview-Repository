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
# Note: Using existing Config recorder "default" in the account
# Config Rules are added to the existing recorder to detect our intentional misconfigurations

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
}

# Detect unrestricted SSH (will flag mongo_sg)
resource "aws_config_config_rule" "restricted_ssh" {
  name = "${var.project}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

# Detect IAM policies with admin access (will flag ec2_role)
resource "aws_config_config_rule" "iam_no_admin" {
  name = "${var.project}-iam-no-admin"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }
}

# S3 versioning check
resource "aws_config_config_rule" "s3_versioning" {
  name = "${var.project}-s3-versioning"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
  }
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
