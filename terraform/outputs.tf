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
