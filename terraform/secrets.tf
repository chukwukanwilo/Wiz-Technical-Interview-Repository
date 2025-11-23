# =============================================================================
# AWS Secrets Manager - MongoDB Credentials
# =============================================================================
# NOTE: This secret must be created MANUALLY in AWS Secrets Manager BEFORE
# running terraform apply, to avoid chicken-and-egg problem.
#
# Secret Name: ${var.project}-mongodb-credentials (e.g., wiz-exercise-mongodb-credentials)
#
# Secret Value (JSON format with MONGO_ prefix):
# {
#   "MONGO_USERNAME": "admin",
#   "MONGO_PASSWORD": "YourSecurePassword123!",
#   "MONGO_DATABASE": "admin"
# }
#
# Create it via AWS CLI:
# aws secretsmanager create-secret \
#   --name wiz-exercise-mongodb-credentials \
#   --description "MongoDB admin credentials" \
#   --secret-string '{"MONGO_USERNAME":"admin","MONGO_PASSWORD":"YourSecurePassword123!","MONGO_DATABASE":"admin"}'

# Data source to reference the manually created secret
data "aws_secretsmanager_secret" "mongodb_credentials" {
  name = "${var.project}-mongodb-credentials"
}

# IAM policy to allow EC2 instance to read the secret
resource "aws_iam_role_policy" "ec2_secrets_access" {
  name = "${var.project}-ec2-secrets-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = data.aws_secretsmanager_secret.mongodb_credentials.arn
      }
    ]
  })
}
