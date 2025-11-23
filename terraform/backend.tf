# Terraform Backend Configuration
# Store state in S3 with DynamoDB locking to prevent concurrent modifications
# This must be created manually before first terraform init:
#
# aws s3 mb s3://wiz-exercise-terraform-state-253490792199 --region us-east-1
# aws s3api put-bucket-versioning --bucket wiz-exercise-terraform-state-253490792199 --versioning-configuration Status=Enabled
# aws dynamodb create-table --table-name wiz-exercise-terraform-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST --region us-east-1

terraform {
  backend "s3" {
    bucket         = "wiz-exercise-terraform-state-253490792199"
    key            = "wiz-exercise/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "wiz-exercise-terraform-locks"
    encrypt        = true
  }
}
