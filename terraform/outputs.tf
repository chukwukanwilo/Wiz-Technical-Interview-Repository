output "mongo_private_ip" {
  value = aws_instance.mongo_vm.private_ip
}

output "mongo_public_ip" {
  value = aws_instance.mongo_vm.public_ip
}

output "s3_bucket" {
  value = aws_s3_bucket.mongo_backups.bucket
}

output "kubeconfig" {
  value = module.eks.kubeconfig
  sensitive = true
}

output "app_backup_bucket_name" {
  description = "S3 bucket name used for app backups"
  value       = aws_s3_bucket.app_backup.bucket
}

output "mongodb_secret_name" {
  description = "AWS Secrets Manager secret name for MongoDB credentials"
  value       = data.aws_secretsmanager_secret.mongodb_credentials.name
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}
