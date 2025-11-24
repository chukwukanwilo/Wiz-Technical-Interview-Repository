# Wiz Technical Exercise - Presentation Guide

**Candidate:** Chucks Nwilo  
**Date:** November 2025  
**Architecture:** AWS EKS + EC2 MongoDB + S3 Backups + ALB Ingress

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Build Approach & Challenges](#build-approach--challenges)
3. [Live Demonstration](#live-demonstration)
4. [Security Misconfigurations](#security-misconfigurations)
5. [Demo Commands Reference](#demo-commands-reference)

---

## Architecture Overview

### Components Deployed
```
Internet
   ↓
Application Load Balancer (ALB)
   ↓
EKS Cluster (Private Subnets)
   ├── 2x Node.js App Pods
   └── AWS Load Balancer Controller
   ↓
MongoDB EC2 VM (Public Subnet)
   ↓
S3 Bucket (Public Backups)
```

### Key Technologies
- **Infrastructure as Code:** Terraform
- **Container Orchestration:** Amazon EKS (Kubernetes 1.30)
- **Application:** Node.js containerized app (tasky-app)
- **Database:** MongoDB 4.0.27 (intentionally outdated)
- **CI/CD:** GitHub Actions with security scanning
- **Security Controls:** CloudTrail, AWS Config Rules

---

## Build Approach & Challenges

### Initial State
The junior engineer's implementation had several critical issues:
- Duplicate Terraform resources causing deployment failures
- MongoDB not starting due to network connectivity issues
- Missing IAM permissions for AWS Load Balancer Controller
- No authentication on MongoDB
- Incomplete security controls

### Challenge 1: Terraform State Conflicts
**Problem:** Multiple VPCs, EKS clusters, and orphaned resources from failed deployments.

**Solution:**
```bash
# Created comprehensive cleanup script
aws eks list-clusters | jq -r '.clusters[]' | xargs -I {} aws eks delete-cluster --name {}
aws ec2 describe-vpcs --filters Name=tag:Project,Values=wiz-exercise | jq -r '.Vpcs[].VpcId' | xargs -I {} aws ec2 delete-vpc --vpc-id {}
# + cleaned up EIPs, NAT Gateways, Security Groups

# Reset Terraform state
aws s3 rm s3://wiz-exercise-terraform-state-253490792199/terraform.tfstate --recursive
aws dynamodb delete-item --table-name wiz-exercise-terraform-locks --key '{"LockID":{"S":"wiz-exercise-terraform-state-253490792199/terraform.tfstate-md5"}}'
```

**Result:** Clean slate for fresh deployment.

---

### Challenge 2: MongoDB Not Starting - Network Connectivity
**Problem:** MongoDB EC2 instance couldn't download packages during user-data execution.

**Root Cause Analysis:**
```bash
# Checked EC2 console logs
aws ec2 get-console-output --instance-id i-0ddb54d770ec2b17a

# Found errors:
# "Cannot find a valid baseurl for repo: amzn2-core"
# "Connection timeout after 5000 ms"
# "Failed running /var/lib/cloud/instance/scripts/part-001"
```

**Diagnosis:** Instance was in public subnet but had **no public IP** → couldn't reach internet via IGW.

**Solution:**
```hcl
# terraform/s3_ec2_iam.tf
resource "aws_instance" "mongo_vm" {
  associate_public_ip_address = true  # ← Added this line
  subnet_id                   = module.vpc.public_subnets[0]
  # ...
}
```

**Verification:**
```bash
# After redeployment
aws ec2 describe-instances --instance-ids i-0bafb5711c4a881f3 --query 'Reservations[0].Instances[0].[PublicIpAddress,State.Name]'
# Output: 204.236.207.35, running

# Verified MongoDB installed
aws ec2 get-console-output --instance-id i-0bafb5711c4a881f3 | grep "mongodb-org"
# Output: "mongodb-org.x86_64 0:4.0.27-1.amzn2"
```

---

### Challenge 3: App Pods CrashLoopBackOff
**Problem:** Pods couldn't connect to MongoDB.

**Root Causes:**
1. Old MongoDB IP in Kubernetes secret (10.20.1.63 → 10.20.1.170 after VM recreation)
2. MongoDB not listening on correct interface (only 127.0.0.1)

**Solution:**
```bash
# Updated connection string to new IP
kubectl delete secret mongodb-credentials
kubectl create secret generic mongodb-credentials \
  --from-literal=MONGO_URI="mongodb://10.20.1.170:27017/tasky"

# Restarted pods
kubectl rollout restart deployment tasky-app

# Verified connectivity from within cluster
kubectl run -i --tty --rm debug --image=busybox --restart=Never -- nc -zv 10.20.1.170 27017
```

**Result:** Pods transitioned from CrashLoopBackOff → Running.

---

### Challenge 4: ALB Not Provisioning - IAM Permissions
**Problem:** AWS Load Balancer Controller couldn't create ALB.

**Error from logs:**
```
api error AccessDenied: User: arn:aws:sts::253490792199:assumed-role/wiz-exercise-ng-eks-node-group/i-... 
is not authorized to perform: elasticloadbalancing:DescribeTargetGroups
```

**Root Cause:** Load Balancer Controller service account had no IAM role annotation (IRSA not configured).

**Solution:**
```bash
# 1. Created IAM role + policy in Terraform (lb-controller-iam.tf)
# 2. Annotated service account
kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::253490792199:role/wiz-exercise-aws-load-balancer-controller

# 3. Restarted controller
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

# 4. Missing permission discovered in logs
# Added: elasticloadbalancing:DescribeListenerAttributes
```

**Result:** ALB successfully provisioned in ~2 minutes.

---

### Challenge 5: Subnet Tags for ALB Discovery
**Problem:** Even with permissions, ALB controller couldn't determine which subnets to use.

**Solution:**
```hcl
# terraform/vpc.tf
module "vpc" {
  # ...
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"  # For internet-facing ALB
  }
  
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"  # For internal ALB
  }
}
```

---

## Live Demonstration

### 1. Infrastructure Verification

**Check running resources:**
```bash
# EKS Cluster
aws eks describe-cluster --name wiz-exercise-eks --query 'cluster.[name,status,endpoint]'

# MongoDB VM
aws ec2 describe-instances --filters Name=tag:Name,Values=wiz-exercise-mongo-vm \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]'

# S3 Buckets
aws s3 ls | grep wiz-exercise

# ALB
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-default-taskyapp`)]'
```

---

### 2. Kubernetes CLI Demonstration

**Cluster access:**
```bash
# Configure kubectl
aws eks update-kubeconfig --name wiz-exercise-eks --region us-east-1

# Verify nodes
kubectl get nodes -o wide
```

**Expected output:**
```
NAME                           STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP
ip-10-20-11-239.ec2.internal   Ready    <none>   17h   v1.30     10.20.11.239  <none>
ip-10-20-12-155.ec2.internal   Ready    <none>   17h   v1.30     10.20.12.155  <none>
```

**Check application pods:**
```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name> --tail=20
```

**Expected output:**
```
NAME                         READY   STATUS    RESTARTS   AGE   IP            NODE
tasky-app-6c87df75c4-nz9mc   1/1     Running   0          30m   10.20.12.159  ip-10-20-12-155...
tasky-app-6c87df75c4-scvlk   1/1     Running   0          30m   10.20.11.46   ip-10-20-11-239...
```

**Verify wizexercise.txt in container:**
```bash
POD=$(kubectl get pod -l app=tasky -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /app/wizexercise.txt
```

**Expected output:**
```
Chucks Nwilo - Wiz Technical Assessment
```

**Check services and ingress:**
```bash
kubectl get svc,ingress
```

**Expected output:**
```
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/tasky-app    ClusterIP   172.20.254.21   <none>        80/TCP    1h

NAME                                  CLASS   HOSTS   ADDRESS                                                                  PORTS   AGE
ingress.networking.k8s.io/tasky-app   alb     *       k8s-default-taskyapp-0ed8858b48-1661588136.us-east-1.elb.amazonaws.com   80      1h
```

**Check cluster-admin binding (intentional misconfiguration):**
```bash
kubectl get clusterrolebinding app-cluster-admin-binding -o yaml
```

---

### 3. Application & Database Proof

**Get ALB URL:**
```bash
ALB_URL=$(kubectl get ingress tasky-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$ALB_URL"
```

**Test application endpoints:**
```bash
# 1. Root endpoint
curl http://$ALB_URL/
# Expected: "Tasky sample app - connect to /todos"

# 2. Verify wizexercise.txt is accessible
curl http://$ALB_URL/wiz-file
# Expected: {"wiz":"Chucks Nwilo - Wiz Technical Assessment\n"}

# 3. Create a TODO in MongoDB
curl -X POST http://$ALB_URL/todos \
  -H 'Content-Type: application/json' \
  -d '{"text":"Live demo - Wiz Security Platform"}'
# Expected: {"insertedId":"<mongo-id>"}

# 4. Retrieve all TODOs (proves data persistence)
curl http://$ALB_URL/todos
# Expected: [{"_id":"...","text":"Live demo - Wiz Security Platform","createdAt":"2025-11-24T..."}]

# 5. Create multiple entries
curl -X POST http://$ALB_URL/todos -H 'Content-Type: application/json' -d '{"text":"Entry 1"}'
curl -X POST http://$ALB_URL/todos -H 'Content-Type: application/json' -d '{"text":"Entry 2"}'
curl http://$ALB_URL/todos | jq 'length'
# Shows count increasing
```

**Verify data in MongoDB directly:**
```bash
# SSH to MongoDB VM (note: SSH is open to 0.0.0.0/0 - intentional misconfiguration)
MONGO_IP=$(cd terraform && terraform output -raw mongo_public_ip)
ssh -i ~/.ssh/your-key.pem ec2-user@$MONGO_IP

# On the VM, query MongoDB
mongo tasky --eval "db.todos.find().forEach(printjson)"
```

**Expected output:**
```json
{
  "_id": ObjectId("69249835d91dfbfe1a902c90"),
  "text": "Live demo - Wiz Security Platform",
  "createdAt": ISODate("2025-11-24T17:39:01.054Z")
}
```

---

## Security Misconfigurations

### 1. SSH Exposed to Internet (0.0.0.0/0)
**Location:** `terraform/s3_ec2_iam.tf`

```hcl
resource "aws_security_group" "mongo_sg" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # ← CRITICAL: Open to world
  }
}
```

**Consequences:**
- Brute force attacks on SSH
- Potential unauthorized access if weak credentials
- Attack surface for lateral movement

**Detection:**
```bash
# AWS Config Rule: restricted-ssh
aws configservice describe-compliance-by-config-rule \
  --config-rule-names restricted-ssh

# Manual verification
aws ec2 describe-security-groups --group-ids sg-07837bebe779b6446 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

**Remediation:**
- Restrict to corporate IP ranges or VPN
- Use AWS Systems Manager Session Manager (no SSH port needed)
- Implement bastion host with MFA

---

### 2. Overly Permissive IAM Role
**Location:** `terraform/s3_ec2_iam.tf`

```hcl
resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # ← CRITICAL
}
```

**Consequences:**
- EC2 compromise = full AWS account compromise
- Can create/delete any resource
- Can escalate privileges, access secrets, modify IAM policies
- Lateral movement to other workloads

**Detection:**
```bash
# AWS Config Rule: iam-policy-no-statements-with-admin-access
aws iam list-attached-role-policies --role-name wiz-exercise-ec2-role

# Check effective permissions
aws iam get-role-policy --role-name wiz-exercise-ec2-role --policy-name AdministratorAccess
```

**Remediation:**
```hcl
# Apply least privilege - MongoDB VM only needs:
resource "aws_iam_policy" "mongo_vm_policy" {
  policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.mongo_backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = data.aws_secretsmanager_secret.mongodb_credentials.arn
      }
    ]
  })
}
```

---

### 3. Public S3 Bucket
**Location:** `terraform/s3_ec2_iam.tf`

```hcl
resource "aws_s3_bucket_policy" "mongo_backups_public" {
  policy = jsonencode({
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"  # ← CRITICAL: Public read
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.mongo_backups.arn}/*"
      }
    ]
  })
}
```

**Consequences:**
- Database backups publicly accessible
- Data breach / sensitive data exposure
- Compliance violations (GDPR, HIPAA, PCI-DSS)

**Detection:**
```bash
# AWS Config Rule: s3-bucket-public-read-prohibited
aws s3api get-bucket-policy --bucket wiz-exercise-mongo-backups-f04e7f02

# Test public access (no credentials)
aws s3 ls s3://wiz-exercise-mongo-backups-f04e7f02/ --no-sign-request
```

**Remediation:**
```hcl
# Remove public access block exceptions
resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  block_public_acls       = true   # ← Changed
  block_public_policy     = true   # ← Changed
  ignore_public_acls      = true   # ← Changed
  restrict_public_buckets = true   # ← Changed
}

# Remove public bucket policy
# resource "aws_s3_bucket_policy" "mongo_backups_public" {} ← Delete
```

---

### 4. Cluster-Admin Role Binding
**Location:** `helm/tasky-app/templates/clusterrolebinding.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-cluster-admin-binding
subjects:
- kind: ServiceAccount
  name: default  # ← Default service account
  namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin  # ← Full cluster access
```

**Consequences:**
- Pod compromise = full cluster compromise
- Can read all secrets (including credentials)
- Can modify/delete any resource in cluster
- Can create privileged pods for container escape

**Detection:**
```bash
kubectl get clusterrolebinding app-cluster-admin-binding -o yaml

# Check what permissions the default SA has
kubectl auth can-i --list --as=system:serviceaccount:default:default
```

**Remediation:**
```yaml
# Create least-privilege Role (not ClusterRole)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tasky-app-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
---
# Create dedicated ServiceAccount (not default)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tasky-app-sa
---
# Bind to Role (not cluster-admin)
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tasky-app-binding
subjects:
- kind: ServiceAccount
  name: tasky-app-sa
roleRef:
  kind: Role
  name: tasky-app-role
```

---

### 5. Outdated MongoDB Version
**Location:** `terraform/user-data-mongo.tpl`

```bash
yum install -y mongodb-org-4.0.27  # Released 2021, EOL Feb 2024
```

**Consequences:**
- Known CVEs unpatched (CVE-2021-20329, CVE-2022-1348, etc.)
- No security updates
- Exploitation via network-accessible services

**Detection:**
```bash
# Check MongoDB version
ssh ec2-user@<mongo-ip> "mongod --version"

# Check for CVEs
curl -s https://nvd.nist.gov/vuln/search/results?form_type=Advanced&cves=on&query=mongodb+4.0
```

**Remediation:**
- Upgrade to MongoDB 6.0+ or 7.0 (current LTS)
- Implement automated patching schedule
- Use managed service (AWS DocumentDB) for auto-patching

---

## Demo Commands Reference

### Quick Demo Script (5 minutes)
```bash
# 1. Show infrastructure
terraform -chdir=terraform output

# 2. Show cluster
kubectl get nodes
kubectl get pods -o wide

# 3. Prove wizexercise.txt exists
POD=$(kubectl get pod -l app=tasky -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /app/wizexercise.txt

# 4. Get ALB URL
ALB_URL=$(kubectl get ingress tasky-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "App URL: http://$ALB_URL"

# 5. Test application + database
curl http://$ALB_URL/wiz-file
curl -X POST http://$ALB_URL/todos -H 'Content-Type: application/json' -d '{"text":"Wiz Demo"}'
curl http://$ALB_URL/todos

# 6. Show security misconfigurations
aws ec2 describe-security-groups --filters Name=group-name,Values=wiz-exercise-mongo-sg \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].CidrIp'
aws iam list-attached-role-policies --role-name wiz-exercise-ec2-role
kubectl get clusterrolebinding app-cluster-admin-binding
```

---

### Full kubectl Demo Commands
```bash
# Cluster info
kubectl cluster-info
kubectl get nodes -o wide

# Application resources
kubectl get all -n default
kubectl get pods -o wide
kubectl get svc,ingress

# Pod details
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- /bin/sh

# Inside pod:
ls -la /app/
cat /app/wizexercise.txt
env | grep MONGO
nc -zv 10.20.1.170 27017

# Secrets
kubectl get secrets
kubectl describe secret mongodb-credentials

# RBAC (show misconfiguration)
kubectl get clusterrolebinding app-cluster-admin-binding -o yaml
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:default

# Networking
kubectl get ingress tasky-app -o yaml
kubectl get svc tasky-app -o yaml

# Events
kubectl get events --sort-by='.lastTimestamp'
```

---

## Presentation Flow Recommendation

### Slide Deck (10-15 slides)
1. **Title Slide** - Your name, exercise overview
2. **Architecture Diagram** - Visual of deployed infrastructure
3. **Technologies Used** - AWS services, tools, frameworks
4. **Build Approach** - High-level methodology
5. **Challenge 1: Terraform State** - Problem + solution
6. **Challenge 2: MongoDB Networking** - Diagnostic process
7. **Challenge 3: Application Connectivity** - Pod crashes
8. **Challenge 4: ALB Permissions** - IAM troubleshooting
9. **Security Misconfig 1** - SSH exposure
10. **Security Misconfig 2** - IAM over-privileges
11. **Security Misconfig 3** - Public S3
12. **Security Misconfig 4** - Cluster-admin
13. **Security Misconfig 5** - Outdated software
14. **Value of Wiz** - How tool detects these issues
15. **Q&A** - Questions slide

### Live Demo (10-15 minutes)
1. **Infrastructure Tour** (3 min)
   - Show AWS Console: VPC, EKS, EC2, S3, ALB
   - Run `terraform output`
   
2. **Kubernetes Walkthrough** (5 min)
   - `kubectl get nodes`
   - `kubectl get pods`
   - `kubectl exec` to show wizexercise.txt
   - `kubectl get ingress`

3. **Application Functionality** (4 min)
   - Browser: Open ALB URL
   - Terminal: `curl` examples
   - Create TODO, retrieve it
   - Show MongoDB persistence

4. **Security Findings** (3 min)
   - Show one misconfiguration in AWS Console
   - Show cluster-admin binding
   - Mention others briefly

---

## Expected Questions & Answers

**Q: Why didn't you use authentication for MongoDB?**  
A: The initial secret wasn't populated when the VM started. In production, I'd use AWS Secrets Manager rotation and ensure secrets exist before deployment. For this demo, I focused on proving connectivity first.

**Q: How would you secure this in production?**  
A: 
1. SSH via SSM Session Manager (no port 22)
2. Least-privilege IAM roles (remove AdministratorAccess)
3. Private S3 with bucket policies + VPC endpoints
4. Pod Security Standards (restricted)
5. Upgrade MongoDB to 7.0 + enable authentication
6. Network policies to limit pod-to-pod traffic
7. WAF in front of ALB

**Q: What would Wiz detect here?**  
A: Wiz would flag:
- Public S3 bucket with sensitive data
- SSH open to 0.0.0.0/0
- EC2 with AdministratorAccess
- Outdated MongoDB with known CVEs
- Cluster-admin binding to default SA
- Missing encryption at rest
- No CloudTrail encryption

**Q: Why did the MongoDB fail initially?**  
A: The EC2 instance was in a public subnet but without a public IP. It couldn't reach the internet via the Internet Gateway to download packages. Adding `associate_public_ip_address = true` fixed it.

**Q: How did you diagnose the ALB issue?**  
A: I checked the Load Balancer Controller logs with `kubectl logs` and saw AccessDenied errors. This indicated missing IAM permissions. I then created an IAM role with IRSA and annotated the service account.

---

## Success Metrics

✅ **Infrastructure Deployed:** All Terraform resources created successfully  
✅ **Application Running:** 2 pods in Running state  
✅ **Database Connectivity:** MongoDB accepting connections, data persisting  
✅ **Internet Access:** ALB serving traffic from public internet  
✅ **wizexercise.txt Present:** File accessible in container  
✅ **Security Controls:** CloudTrail + AWS Config deployed  
✅ **CI/CD Pipelines:** Both workflows passing with security scans  
✅ **Misconfigurations Identified:** 5 intentional issues documented

---

## Cleanup Commands
```bash
# Delete Kubernetes resources
helm uninstall tasky-app

# Destroy infrastructure
cd terraform
terraform destroy -auto-approve

# Delete secret
aws secretsmanager delete-secret \
  --secret-id wiz-exercise-mongodb-credentials \
  --force-delete-without-recovery
```

---

**End of Presentation Guide**
