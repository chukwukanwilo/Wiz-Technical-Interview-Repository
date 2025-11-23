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
  default     = null
  description = "Optional: provide a name for the backup bucket. If null, Terraform will generate one."
}

variable "key_name" {
  type        = string
  description = "EC2 keypair name for SSH access to Mongo VM"
}

variable "eks_node_group_desired" {
  type    = number
  default = 2
}
