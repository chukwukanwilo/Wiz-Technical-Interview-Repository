variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "wiz-exercise"
}

variable "backup_bucket_name" {
  type        = string
  default     = ""
  description = "S3 bucket name for backups (auto-generated if empty)"
}

variable "eks_node_group_desired" {
  type    = number
  default = 2
}
