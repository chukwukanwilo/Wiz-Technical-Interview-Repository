# Wiz Technical Exercise - Complete Implementation

> Security note: this repo intentionally includes insecure configurations for the exercise. Do not reuse in production.

## Overview
This repository delivers the Wiz exercise end-to-end:
- Terraform infrastructure (VPC, EKS, MongoDB VM, S3)
- Containerized Node.js Todo app using MongoDB
- Helm chart for K8s deployment (uses MONGO_URI env var)
- Two CI/CD pipelines (infra and app) with security scanning
- Cloud-native security controls (CloudTrail, AWS Config rules)

## Architecture
```
GitHub Actions (infra.yml, app.yml)
        ↓
AWS: VPC (public/private) + EKS (private) + EC2 Mongo (old) + S3 backups (public)
        ↓
Kubernetes: tasky-app Deployment + Service + Ingress (ALB) + cluster-admin binding
```

## Intentional Insecurities (for demo)
- MongoDB VM has AdministratorAccess IAM role
- SSH exposed 0.0.0.0/0
- S3 backups bucket public read/list
- App service account bound to ClusterRole cluster-admin
- MongoDB 4.0.x (outdated)

## Prerequisites
- AWS CLI, Terraform (>= 1.3), kubectl, Docker, Helm 3
- An EC2 key pair name for SSH (set in terraform vars)

## One-time secret (must exist before Terraform)
Create this in AWS Secrets Manager (region us-east-1):
```
Name: wiz-exercise-mongodb-credentials
Value (JSON):
{
  "MONGO_USERNAME": "admin",
  "MONGO_PASSWORD": "YourSecurePassword123!",
  "MONGO_DATABASE": "admin"
}
```

CLI example:
```bash
aws secretsmanager create-secret \
  --name wiz-exercise-mongodb-credentials \
  --description "MongoDB admin credentials" \
  --secret-string '{"MONGO_USERNAME":"admin","MONGO_PASSWORD":"YourSecurePassword123!","MONGO_DATABASE":"admin"}' \
  --region us-east-1
```

## Deploy infrastructure
### GitHub Actions (recommended)
- Push changes under `terraform/**` or manually run workflow: .github/workflows/infra.yml

### Local (alternative)
```bash
cd terraform
terraform init
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
project    = "wiz-exercise"
key_name   = "your-ec2-key-name"
eks_node_group_desired = 2
EOF
terraform apply -auto-approve
```

## Build & deploy the app
### CI/CD (recommended)
- Push changes under `app/**` or `k8s/**` to trigger .github/workflows/app.yml
- Pipeline: npm audit → Trivy scan → build/push ECR → deploy

### Manual via Helm
```bash
# Configure kubectl
aws eks update-kubeconfig --name wiz-exercise-eks --region us-east-1

# Create Kubernetes Secret with Mongo connection string (requirement: env var)
MONGO_IP=$(terraform -chdir=terraform output -raw mongo_private_ip)
kubectl create secret generic mongodb-credentials \
  --from-literal=MONGO_URI="mongodb://admin:YourSecurePassword123!@${MONGO_IP}:27017/tasky?authSource=admin"

# Deploy chart
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
IMAGE_REPO="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/wiz-tasky"
helm install tasky-app ./helm/tasky-app \
  --set image.repository=${IMAGE_REPO} \
  --set image.tag=latest
```

## Verify
```bash
# App up
kubectl get pods,svc,ingress

# File exists in container
POD=$(kubectl get pod -l app=tasky -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -- cat /app/wizexercise.txt

# App endpoints
curl http://<ALB_URL>/
curl http://<ALB_URL>/wiz-file
curl -X POST http://<ALB_URL>/todos -H 'Content-Type: application/json' -d '{"text":"hello"}'
curl http://<ALB_URL>/todos

# Mongo VM and data
MONGO_PUB=$(terraform -chdir=terraform output -raw mongo_public_ip)
ssh -i ~/.ssh/your-key.pem ec2-user@${MONGO_PUB}
# on VM:
mongo -u admin -p --authenticationDatabase admin --eval 'db.getMongo().getDB("tasky").todos.find().forEach(printjson)'

# Backups are public
BUCKET=$(terraform -chdir=terraform output -raw s3_bucket)
aws s3 ls s3://${BUCKET}/backups/ --no-sign-request
```

## CI/CD pipelines
- infra.yml
  - Checkov + tfsec (report), terraform validate/plan/apply (main only)
- app.yml
  - npm audit, Trivy image scan, build/push to ECR, kubectl/Helm deploy

## Security controls
- CloudTrail trail (multi-region) to S3
- AWS Config rules: public S3, unrestricted SSH, admin policies, S3 versioning

## Repository layout
```
app/            # Node app, Dockerfile, wizexercise.txt
helm/tasky-app/ # Helm chart (uses MONGO_URI from K8s Secret)
k8s/            # Raw manifests (reference)
terraform/      # IaC (VPC, EKS, EC2 Mongo, S3, Config, CloudTrail)
.github/workflows/  # CI/CD
ops/            # EC2 user-data scripts
scripts/        # helper scripts
```

## Cleanup
```bash
helm uninstall tasky-app || true
cd terraform && terraform destroy -auto-approve
aws secretsmanager delete-secret \
  --secret-id wiz-exercise-mongodb-credentials \
  --force-delete-without-recovery
```

## Notes
- Per exercise, cluster-admin binding is intentional.
- S3 backups are intentionally public for detection.
- EKS runs in private subnets; ALB exposes the app.
