# Wiz Technical Exercise (scaffold)

This repository contains a scaffold to run the Wiz Technical Exercise (AWS-focused). The scaffold includes:

- Terraform infra (VPC, EKS, EC2 for Mongo, S3)
- A small Node.js app under `app/` with Dockerfile
- Kubernetes manifests under `k8s/`
- Operational scripts under `ops/`
- GitHub Actions workflows under `.github/workflows/`
- Helper scripts in `scripts/` and a `Makefile` to coordinate common tasks

Prerequisites
 - AWS credentials configured locally (AWS CLI)
 - terraform installed
 - kubectl installed
 - docker installed (for building images)

Quickstart (local)

1. Populate Terraform variables:

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars and set key_name and any other vars
```

2. Apply infra (will create S3, EC2, EKS):

```sh
make infra
```

3. Build and push the app image to ECR (set `ECR_REGISTRY` and `ECR_REPO` env vars):

```sh
export ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com
export ECR_REPO=wiz-tasky
make build
```

4. Generate kubeconfig from Terraform outputs:

```sh
make kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
```

5. Deploy the app to the cluster (set IMAGE or ECR vars):

```sh
IMAGE=${ECR_REGISTRY}/${ECR_REPO}:latest make deploy
```

Notes & Security
- The scaffold intentionally includes insecure items for the exercise (public S3 ACL, Admin IAM role for EC2, cluster-admin ClusterRoleBinding). Do not copy these settings to production.

If you want, I can further automate creation of the ECR repo, or add GitHub Action secrets examples.
# Wiz-Technical-Interview-Repository
This repository will contain all necessary scripts and artifacts for the WIZ take home assessment
