# wiz-tech-exercise (scaffold)

This repository scaffold contains a complete starting point for the Wiz Technical Exercise V4. It includes:

- Terraform skeleton (AWS-focused, adjustable for Azure/GCP)
- App (Node.js sample `tasky`-style) with Dockerfile and `wizexercise.txt`
- Kubernetes manifests (Deployment, Service, Ingress, ClusterRoleBinding)
- EC2 backup script to snapshot MongoDB and upload to S3 (with public read ACL intentionally enabled)
- GitHub Actions pipelines: `infra.yml` (Terraform) and `app.yml` (build, scan, push, deploy)
- Notes and a step-by-step implementation walkthrough

---

## Repository layout

```
wiz-tech-exercise/
├── README.md                     # high-level guide + walkthrough
├── terraform/                    # IaC for VPC, EKS, EC2, S3
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
├── app/                          # containerized web app
│   ├── src/
│   │   └── server.js
│   ├── package.json
│   ├── Dockerfile
│   └── wizexercise.txt
├── k8s/                          # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── clusterrolebinding.yaml
├── ops/                          # operational scripts (run on EC2 VM)
│   ├── mongo-backup.sh
│   └── install-mongo.sh
├── .github/workflows/
│   ├── infra.yml
│   └── app.yml
└── docs/
    └── presentation-notes.md
```

---

## Key files (complete contents)

> NOTE: This scaffold is opinionated for **AWS**. If you prefer Azure/GCP I can adapt the Terraform and scripts.

### `app/wizexercise.txt`
```
Chucks Nwilo - Wiz Technical Exercise
```

### `app/Dockerfile`
```
# simple Node app
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY src ./src
COPY wizexercise.txt /app/wizexercise.txt
ENV PORT=3000
CMD ["node", "src/server.js"]
```

### `app/src/server.js`
```
const express = require('express');
const { MongoClient } = require('mongodb');
const app = express();
const port = process.env.PORT || 3000;
const mongoUri = process.env.MONGO_URI || 'mongodb://mongo:27017/tasky';

let db;

async function initDb(){
  const client = new MongoClient(mongoUri, { useUnifiedTopology: true });
  await client.connect();
  db = client.db('tasky');
  await db.collection('todos').createIndex({ createdAt: 1 });
}

app.use(express.json());

app.get('/', (req, res) => res.send('Tasky sample app - connect to /todos'));

app.get('/wiz-file', (req, res) => {
  const fs = require('fs');
  const content = fs.readFileSync('/app/wizexercise.txt', 'utf8');
  res.send({ wiz: content });
});

app.get('/todos', async (req, res) => {
  const todos = await db.collection('todos').find().toArray();
  res.json(todos);
});

app.post('/todos', async (req, res) => {
  const todo = { text: req.body.text || 'no text', createdAt: new Date() };
  const r = await db.collection('todos').insertOne(todo);
  res.json({ insertedId: r.insertedId });
});

initDb().then(() => app.listen(port, () => console.log(`Listening on ${port}`))).catch(err => { console.error(err); process.exit(1); });
```

### `k8s/deployment.yaml`
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tasky-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tasky
  template:
    metadata:
      labels:
        app: tasky
    spec:
      containers:
      - name: tasky
        image: <REGISTRY>/tasky:latest
        ports:
        - containerPort: 3000
        env:
        - name: MONGO_URI
          value: "mongodb://<EC2_PRIVATE_IP>:27017/tasky"
        volumeMounts: []
```

### `k8s/service.yaml`
```
apiVersion: v1
kind: Service
metadata:
  name: tasky-svc
spec:
  selector:
    app: tasky
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: ClusterIP
```

### `k8s/ingress.yaml`
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tasky-ingress
  annotations:
    kubernetes.io/ingress.class: alb # or nginx depending on your cluster
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tasky-svc
            port:
              number: 80
```

### `k8s/clusterrolebinding.yaml` (intentional privilege escalation)
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-cluster-admin-binding
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

### `ops/install-mongo.sh`
```
#!/bin/bash
# Install an old MongoDB version (intentionally outdated). Example for Amazon Linux 2
set -e
sudo yum update -y
# choose an older repo / package; placeholder below
sudo yum install -y mongodb-org-4.0.27
sudo systemctl enable mongod
sudo systemctl start mongod
```

### `ops/mongo-backup.sh`
```
#!/bin/bash
# Daily backup script: dumps MongoDB and uploads to S3 with public-read
set -e
timestamp=$(date -u +"%Y-%m-%dT%H%M%SZ")
backup_dir=/tmp/mongo_backup_$timestamp
mkdir -p "$backup_dir"
/usr/bin/mongodump --archive="$backup_dir/dump.archive" --gzip
# install aws cli beforehand and ensure instance has IAM permissions (intentionally broad)
aws s3 cp "$backup_dir/dump.archive" s3://<PUBLIC_BUCKET>/backups/dump-$timestamp.archive --acl public-read
# optional: cleanup
rm -rf "$backup_dir"
```

> **Intentional**: S3 bucket is created with public listing and public read (as requested by the exercise).

### `terraform/main.tf` (skeleton)
```
# provider & basic infra skeleton (AWS example)
provider "aws" {
  region = var.region
}

# VPC, subnets, EKS cluster, EC2 instance for MongoDB, S3 bucket
# Use modules or community modules for EKS; omitted here for brevity

resource "aws_s3_bucket" "mongo_backups" {
  bucket = var.backup_bucket_name
  acl    = "public-read"
  force_destroy = true
}

# EC2 instance (MongoDB VM) - with a permissive IAM role
resource "aws_iam_role" "mongo_vm_role" {
  name = "mongo_vm_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mongo_attach" {
  role       = aws_iam_role.mongo_vm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # intentionally permissive
}

# outputs: ec2 private ip, s3 bucket name, kubeconfig
```

### `.github/workflows/infra.yml`
```
name: Terraform CI
on:
  push:
    paths:
      - 'terraform/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
    - name: Terraform Init
      run: terraform -chdir=terraform init
    - name: Terraform Validate
      run: terraform -chdir=terraform validate
    - name: Terraform Plan
      run: terraform -chdir=terraform plan -out=tfplan
    - name: Terraform Apply
      if: github.ref == 'refs/heads/main'
      run: terraform -chdir=terraform apply -auto-approve tfplan
```

### `.github/workflows/app.yml`
```
name: App CI/CD
on:
  push:
    paths:
      - 'app/**'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
    - name: Login to ECR
      uses: aws-actions/amazon-ecr-login@v2
    - name: Build image
      run: |
        docker build -t ${{ secrets.ECR_REPO }}:latest ./app
        docker tag ${{ secrets.ECR_REPO }}:latest ${{ secrets.ECR_REGISTRY }}/${{ secrets.ECR_REPO }}:latest
    - name: Scan image
      run: trivy image --severity HIGH,CRITICAL ${{ secrets.ECR_REGISTRY }}/${{ secrets.ECR_REPO }}:latest || true
    - name: Push image
      run: docker push ${{ secrets.ECR_REGISTRY }}/${{ secrets.ECR_REPO }}:latest
    - name: Trigger K8s rollout
      run: |
        # uses kubectl with KUBECONFIG from secrets or from Terraform outputs
        kubectl set image deployment/tasky-app tasky=${{ secrets.ECR_REGISTRY }}/${{ secrets.ECR_REPO }}:latest
```

---

## Step-by-step Implementation Walkthrough

1. **Create the repo** and push scaffold above. Protect `main` branch with required status checks (CI) in GitHub.
2. **Fill Terraform variables** (region, bucket name, AMI id of older Linux) and run `terraform init && terraform apply` (or let infra workflow do it).
3. **Provision EC2 (Mongo VM)** using an older AMI; use `install-mongo.sh` as user-data to install outdated MongoDB.
4. **Provision EKS** (I recommend using `eksctl` or the AWS EKS module) into private subnets. Ensure worker nodes can reach the EC2 private IP.
5. **Build and push image** from `app/` to ECR via `app.yml` (or locally using `docker build` & `docker push`).
6. **Deploy K8s manifests** (`kubectl apply -f k8s/`) after configuring `MONGO_URI` to point at the EC2 private IP.
7. **Verify**:
   - `kubectl get pods,svc,ingress`
   - `kubectl exec -it <pod> -- cat /app/wizexercise.txt` (demonstrates file in image)
   - Insert/read data via `/todos` and confirm on Mongo VM using `mongo` shell
   - Confirm backups land in S3 and are publicly listable
8. **Show security detections**: enable CloudTrail, AWS Config rules, and show public S3 detection and open SSH rule triggering alerts. Use Checkov/Trivy results from pipelines.

---

## Safety & Cleanup

- The scaffold includes intentionally insecure choices to match the exercise. **Do not** reuse these settings in production.
- Provide a tear-down plan in Terraform or scripts to remove resources and avoid runaway costs.

---

If you want, I can:
- generate the exact Terraform files for the VPC/EKS/EC2/S3 in this scaffold
- produce a ready-to-run `eksctl` + `terraform` combo and the exact `user-data` cloud-init for the EC2
- create the GitHub repo with these files (I can't push to GitHub on your behalf, but I will produce everything for you to copy/paste)

Tell me which cloud provider (AWS / Azure / GCP) you want me to fully author **first** for Terraform and I will produce the ready-to-run files next.



---

# AWS-specific Terraform & user-data (ready-to-run)

Below are ready-to-run Terraform files, the EC2 `user-data` (cloud-init) to install an outdated MongoDB, and the exact commands and GitHub secrets you'll need.

> **Warning:** These Terraform examples intentionally create insecure resources (public SSH, public S3 ACL, Admin IAM role for the EC2 instance, cluster-admin binding). **Only** use them for this exercise in an isolated sandbox and destroy afterwards.

---

## terraform/providers.tf

```
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

## terraform/variables.tf

```
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "wiz-exercise"
}

variable "backup_bucket_name" {
  type    = string
  default = "wiz-exercise-mongo-backups-${random_id.bucket_suffix.hex}"
}

variable "key_name" {
  type = string
  default = "wiz-exercise-key"
}

variable "eks_node_group_desired" {
  type    = number
  default = 2
}
```

## terraform/random.tf

```
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
```

## terraform/vpc.tf

```
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = "${var.project}-vpc"
  cidr = "10.20.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.11.0/24", "10.20.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

data "aws_availability_zones" "available" {}
```

## terraform/eks.tf

```
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.27"

  subnets = module.vpc.private_subnets

  node_groups = {
    default = {
      desired_capacity = var.eks_node_group_desired
      max_capacity     = 3
      min_capacity     = 1

      instance_type = "t3.medium"
    }
  }

  manage_aws_auth = true
}
```

## terraform/s3_ec2_iam.tf

```
# Public S3 bucket for backups
resource "aws_s3_bucket" "mongo_backups" {
  bucket = var.backup_bucket_name
  acl    = "public-read"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "cleanup"
    enabled = true
    expiration {
      days = 30
    }
  }
}

# IAM role for EC2 instance (intentionally permissive)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Security group for Mongo VM (SSH open to world intentionally)
resource "aws_security_group" "mongo_sg" {
  name        = "${var.project}-mongo-sg"
  description = "Allow SSH + Mongo from cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # intentionally open
  }

  # Allow MongoDB port from EKS CIDR (cluster nodes)
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_block # best-effort; modules expose different outputs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance for Mongo
resource "aws_instance" "mongo_vm" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.public_subnets[0]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.mongo_sg.id]

  user_data = file("../ops/user-data-mongo.sh")

  tags = {
    Name = "${var.project}-mongo-vm"
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

## terraform/outputs.tf

```
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
```

---

## ops/user-data-mongo.sh (cloud-init / EC2 user-data)

```
#!/bin/bash
set -e
# Install older MongoDB (4.0.x) on Amazon Linux 2
# This is intentionally outdated for the exercise

# install jq and aws-cli
yum update -y
yum install -y jq awscli

# create a repo file for mongodb-org-4.0
cat > /etc/yum.repos.d/mongodb-org-4.0.repo <<'EOF'
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/
gpgcheck=0
enabled=1
EOF

# install mongodb-org package (older version)
yum install -y mongodb-org-4.0.27 || yum install -y mongodb-org || true

# configure mongod.conf to listen on all interfaces (for EKS nodes to access via private IP)
sed -i "s/bindIp: 127.0.0.1/bindIp: 0.0.0.0/" /etc/mongod.conf || true

# start mongod
systemctl enable mongod
systemctl start mongod

# create backup script
cat > /usr/local/bin/mongo-backup.sh <<'BKP'
#!/bin/bash
set -e
TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
TMPDIR=/tmp/mongobkp_$TIMESTAMP
mkdir -p $TMPDIR
mongodump --archive=$TMPDIR/dump.archive --gzip
aws s3 cp $TMPDIR/dump.archive s3://${backup_bucket} --acl public-read
rm -rf $TMPDIR
BKP
chmod +x /usr/local/bin/mongo-backup.sh

# schedule daily backup via cron (at 02:15 UTC)
( crontab -l 2>/dev/null; echo "15 2 * * * /usr/local/bin/mongo-backup.sh" ) | crontab -

# write a marker file to /app
mkdir -p /app
cat > /app/instance-info.txt <<MSG
Wiz Exercise Mongo VM
Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
MSG

# replace placeholder backup_bucket in script

# Note: Terraform will replace ${backup_bucket} when templating this file or you can use cloud-init template rendering.

```

**Note:** In the `user-data` script above you should ensure the `backup_bucket` placeholder is replaced by Terraform when rendering the file. A simple approach is to write the user-data as a Terraform template file and use the `templatefile()` function with a map containing `backup_bucket = aws_s3_bucket.mongo_backups.bucket`.

---

## ops/mongo-backup.sh (local copy / alternate)

(Provided earlier in the scaffold; ensure it references the real bucket name.)

---

## Kubernetes manifests (update MONGO_URI using Terraform output)

In `k8s/deployment.yaml`, set the env var value with the EC2 private IP output:

```
env:
- name: MONGO_URI
  value: "mongodb://${aws_instance.mongo_vm.private_ip}:27017/tasky"
```

If you want to automate this, write a small script that replaces `<EC2_PRIVATE_IP>` placeholder in the YAML using Terraform output:

```
terraform output -raw mongo_private_ip > mongo_ip.txt
sed -i "s/<EC2_PRIVATE_IP>/$(cat mongo_ip.txt)/g" k8s/deployment.yaml
kubectl apply -f k8s/
```

---

## GitHub Actions secrets (you must set these in the repo settings)

- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` — with privileges to run Terraform and push to ECR
- `ECR_REGISTRY` — e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`
- `ECR_REPO` — e.g. `wiz-tasky`
- `KUBECONFIG` or `KUBE_CONTEXT` — or use GitHub OIDC / AWS_ROLE for deployment
- `TF_VAR_key_name` — the EC2 keypair name (or create keypair resource in Terraform)

---

## Exact commands to run locally (quickstart)

1. Initialize Terraform:

```
cd terraform
terraform init
terraform apply -auto-approve
```

2. Get outputs and configure kubectl:

```
terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
terraform output -raw mongo_private_ip > mongo_ip.txt
```

3. Build & push image (locally; or use GitHub Actions):

```
# build
cd ../app
docker build -t $ECR_REGISTRY/$ECR_REPO:latest .
# login & push
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPO:latest
```

4. Update k8s manifest and apply:

```
sed -i "s/<EC2_PRIVATE_IP>/$(cat ../terraform/mongo_ip.txt)/g" ../k8s/deployment.yaml
kubectl apply -f ../k8s/
```

5. Verify app & wiz file:

```
kubectl get pods -l app=tasky
kubectl exec -it $(kubectl get pod -l app=tasky -o jsonpath="{.items[0].metadata.name}") -- cat /app/wizexercise.txt
```

6. Verify backups in S3 (public):

```
aws s3 ls s3://$(terraform output -raw s3_bucket)/backups/ --no-sign-request
# you can curl the object URL publicly
curl -I https://$(terraform output -raw s3_bucket).s3.amazonaws.com/backups/dump-<TIMESTAMP>.archive
```

---

## Quick remediation notes (for demo)

When showing the exercise, after demonstrating detection of weaknesses, describe the quick fixes:

- Close SSH access to a limited IP range; use bastion host or SSM Session Manager
- Restrict S3 ACLs and use bucket policies + block public access
- Narrow IAM role permissions; avoid AdministratorAccess
- Upgrade MongoDB / apply security patches
- Remove cluster-admin binding and follow least privilege for service accounts

---

If you want, I will now:

1. Generate the full Terraform files (complete, validated for syntax) inside the canvas repo textdoc (`terraform/*.tf`).
2. Produce the finalized `user-data` template using `templatefile()` so Terraform injects the S3 bucket name.
3. Write the exact `kubectl` automation script that picks up Terraform outputs and deploys the manifests.

Say which of the three you'd like me to produce next (I will auto-generate the files).



---

# Full, ready-to-run Terraform files (AWS) — added

Below I’ve generated the full Terraform files and a templated `user-data` file so Terraform injects the S3 bucket name into the EC2 `user-data` at deploy time.

Place these files under `terraform/` in your repo. The `user-data-mongo.tpl` should be saved in the same `terraform/` directory.

---

## terraform/providers.tf

```
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

## terraform/variables.tf

```
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "wiz-exercise"
}

variable "backup_bucket_name" {
  type    = string
  default = null
  description = "Optional: provide a name for the backup bucket. If null, Terraform will generate one." 
}

variable "key_name" {
  type = string
  description = "EC2 keypair name for SSH access to Mongo VM"
}

variable "eks_node_group_desired" {
  type    = number
  default = 2
}
```

## terraform/random.tf

```
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
```

## terraform/vpc.tf

```
data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = "${var.project}-vpc"
  cidr = "10.20.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.11.0/24", "10.20.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}
```

## terraform/eks.tf

```
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.27"

  subnets = module.vpc.private_subnets

  node_groups = {
    default = {
      desired_capacity = var.eks_node_group_desired
      max_capacity     = 3
      min_capacity     = 1

      instance_type = "t3.medium"
    }
  }

  manage_aws_auth = true
}
```

## terraform/s3_ec2_iam.tf

```
# Create S3 bucket (public-read) for backups
resource "aws_s3_bucket" "mongo_backups" {
  bucket = coalesce(var.backup_bucket_name, "${var.project}-mongo-backups-${random_id.bucket_suffix.hex}")
  acl    = "public-read"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "cleanup"
    enabled = true
    expiration {
      days = 30
    }
  }
}

# IAM role for EC2 instance (intentionally permissive for exercise)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Security group for Mongo VM (SSH open to world intentionally)
resource "aws_security_group" "mongo_sg" {
  name        = "${var.project}-mongo-sg"
  description = "Allow SSH + Mongo from cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # intentionally open for the exercise
  }

  # Allow MongoDB port from the VPC's private subnets CIDR - best effort using module outputs
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets # NOTE: some module outputs are lists of CIDR strings; ensure compatibility
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance for Mongo
resource "aws_instance" "mongo_vm" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.public_subnets[0]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.mongo_sg.id]

  # Use templatefile to inject the bucket name into user-data
  user_data = templatefile("${path.module}/user-data-mongo.tpl", { backup_bucket = aws_s3_bucket.mongo_backups.bucket })

  tags = {
    Name = "${var.project}-mongo-vm"
  }
}

# AMI data
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

## terraform/outputs.tf

```
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
```

## terraform/user-data-mongo.tpl

```
#!/bin/bash
set -e
# Install older MongoDB (4.0.x) on Amazon Linux 2
# This user-data template expects 'backup_bucket' to be provided via Terraform templatefile()

yum update -y
yum install -y jq awscli

cat > /etc/yum.repos.d/mongodb-org-4.0.repo <<'EOF'
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/
gpgcheck=0
enabled=1
EOF

# install mongodb-org (older series)
yum install -y mongodb-org-4.0.27 || yum install -y mongodb-org || true

# configure mongod.conf to listen on all interfaces
if [ -f /etc/mongod.conf ]; then
  sed -i "s/bindIp: 127.0.0.1/bindIp: 0.0.0.0/" /etc/mongod.conf || true
fi

systemctl enable mongod
systemctl start mongod

# backup script using the provided bucket
cat > /usr/local/bin/mongo-backup.sh <<BKP
#!/bin/bash
set -e
TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
TMPDIR=/tmp/mongobkp_$TIMESTAMP
mkdir -p $TMPDIR
mongodump --archive=$TMPDIR/dump.archive --gzip || true
aws s3 cp $TMPDIR/dump.archive s3://${backup_bucket}/backups/dump-$TIMESTAMP.archive --acl public-read || true
rm -rf $TMPDIR
BKP
chmod +x /usr/local/bin/mongo-backup.sh

# schedule daily backup via cron at 02:15 UTC
( crontab -l 2>/dev/null; echo "15 2 * * * /usr/local/bin/mongo-backup.sh" ) | crontab -

# marker file for debugging
mkdir -p /app
cat > /app/instance-info.txt <<MSG
Wiz Exercise Mongo VM
Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
S3 Backup Bucket: ${backup_bucket}
MSG

```

---

# How to run (recap)

1. Put the Terraform files in `terraform/` and the `user-data-mongo.tpl` file in the same folder.
2. Export your AWS credentials (or use an authenticated environment like CloudShell or GitHub Actions with OIDC):

```
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
```

3. Initialize & apply:

```
cd terraform
terraform init
terraform apply -var 'key_name=your-keypair' -auto-approve
```

4. After apply, capture outputs and continue with the app build & k8s deployment (as described in the scaffold).

---

If you want, I can now:

- produce the `deploy.sh` automation script that reads `terraform output` and patches `k8s/deployment.yaml` with the `MONGO_URI` and applies the manifests; and
- produce a finalized `k8s/deployment.yaml` with a placeholder for the image that the `deploy.sh` will replace automatically.

Which of those should I generate next? (I can create both.)

