#!/usr/bin/env bash
set -euo pipefail

# cleanup-complete.sh
# Complete cleanup of ALL wiz-exercise resources to start fresh

REGION="us-east-1"
PROJECT="wiz-exercise"

echo "==> Complete Cleanup of ALL wiz-exercise Resources"
echo "This will delete EVERYTHING and start fresh!"
echo ""
read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""

# 1. Delete Config Rules
echo "==> Step 1: Deleting AWS Config Rules"
for rule in "${PROJECT}-s3-public-read" "${PROJECT}-restricted-ssh" "${PROJECT}-iam-no-admin" "${PROJECT}-s3-versioning"; do
  if aws configservice describe-config-rules --config-rule-names "$rule" &>/dev/null; then
    echo "  Deleting Config rule: $rule"
    aws configservice delete-config-rule --config-rule-name "$rule" || true
  fi
done

# 2. Delete S3 Buckets (force delete all objects)
echo ""
echo "==> Step 2: Deleting S3 Buckets"
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT}')].Name" --output text)
for bucket in $BUCKETS; do
  echo "  Force deleting S3 bucket: $bucket"
  aws s3 rb "s3://${bucket}" --force || true
done

# Also delete cloudtrail bucket
CLOUDTRAIL_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudtrail')].Name" --output text)
for bucket in $CLOUDTRAIL_BUCKETS; do
  if [[ $bucket == *"wiz-exercise"* ]]; then
    echo "  Force deleting CloudTrail bucket: $bucket"
    aws s3 rb "s3://${bucket}" --force || true
  fi
done

# 3. Delete CloudTrail
echo ""
echo "==> Step 3: Deleting CloudTrail"
if aws cloudtrail describe-trails --query "trailList[?Name=='${PROJECT}-trail'].Name" --output text | grep -q "${PROJECT}-trail"; then
  echo "  Deleting CloudTrail: ${PROJECT}-trail"
  aws cloudtrail delete-trail --name "${PROJECT}-trail" --region $REGION || true
fi

# 4. Delete EC2 Instances
echo ""
echo "==> Step 4: Deleting EC2 Instances"
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PROJECT}-mongo-vm" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

if [ -n "$INSTANCES" ]; then
  for instance in $INSTANCES; do
    echo "  Terminating instance: $instance"
    aws ec2 terminate-instances --instance-ids $instance || true
  done
  
  echo "  Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCES 2>/dev/null || sleep 60
fi

# 5. Delete EKS Clusters and Node Groups
echo ""
echo "==> Step 5: Deleting EKS Clusters"

# Delete wiz-exercise-eks node groups first
NODEGROUPS=$(aws eks list-nodegroups --cluster-name "${PROJECT}-eks" --query 'nodegroups' --output text 2>/dev/null || echo "")
if [ -n "$NODEGROUPS" ]; then
  for ng in $NODEGROUPS; do
    echo "  Deleting node group: $ng"
    aws eks delete-nodegroup --cluster-name "${PROJECT}-eks" --nodegroup-name "$ng" || true
  done
  
  echo "  Waiting for node groups to delete..."
  for ng in $NODEGROUPS; do
    while aws eks describe-nodegroup --cluster-name "${PROJECT}-eks" --nodegroup-name "$ng" &>/dev/null; do
      echo "    Node group $ng still deleting... waiting 30s"
      sleep 30
    done
  done
fi

# Delete cluster
if aws eks describe-cluster --name "${PROJECT}-eks" &>/dev/null; then
  echo "  Deleting EKS cluster: ${PROJECT}-eks"
  aws eks delete-cluster --name "${PROJECT}-eks" --region $REGION || true
  
  echo "  Waiting for cluster to delete..."
  while aws eks describe-cluster --name "${PROJECT}-eks" &>/dev/null; do
    echo "    Cluster still deleting... waiting 30s"
    sleep 30
  done
fi

# Also delete old cluster
NODEGROUPS_OLD=$(aws eks list-nodegroups --cluster-name "my-wiz-test-assessment-cluster" --query 'nodegroups' --output text 2>/dev/null || echo "")
if [ -n "$NODEGROUPS_OLD" ]; then
  for ng in $NODEGROUPS_OLD; do
    echo "  Deleting old node group: $ng"
    aws eks delete-nodegroup --cluster-name "my-wiz-test-assessment-cluster" --nodegroup-name "$ng" || true
  done
  
  echo "  Waiting for old node groups to delete..."
  for ng in $NODEGROUPS_OLD; do
    while aws eks describe-nodegroup --cluster-name "my-wiz-test-assessment-cluster" --nodegroup-name "$ng" &>/dev/null; do
      sleep 30
    done
  done
fi

if aws eks describe-cluster --name "my-wiz-test-assessment-cluster" &>/dev/null; then
  echo "  Deleting old EKS cluster: my-wiz-test-assessment-cluster"
  aws eks delete-cluster --name "my-wiz-test-assessment-cluster" --region $REGION || true
  
  while aws eks describe-cluster --name "my-wiz-test-assessment-cluster" &>/dev/null; do
    sleep 30
  done
fi

# 6. Delete Load Balancers
echo ""
echo "==> Step 6: Deleting Load Balancers"
# Classic ELBs
CLASSIC_ELBS=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text 2>/dev/null || echo "")
for elb in $CLASSIC_ELBS; do
  echo "  Deleting classic ELB: $elb"
  aws elb delete-load-balancer --load-balancer-name "$elb" || true
done

# ALBs/NLBs
ALBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'wiz')].LoadBalancerArn" --output text 2>/dev/null || echo "")
for alb in $ALBS; do
  echo "  Deleting ALB/NLB: $alb"
  aws elbv2 delete-load-balancer --load-balancer-arn "$alb" || true
done

echo "  Waiting 60s for ELBs to fully delete..."
sleep 60

# 7. Delete Security Groups
echo ""
echo "==> Step 7: Deleting Security Groups"
# Get all VPCs first
VPCS=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text)
for vpc in $VPCS; do
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc" \
    --query "SecurityGroups[?contains(GroupName, '${PROJECT}') && GroupName!='default'].GroupId" \
    --output text 2>/dev/null || echo "")
  
  for sg in $SGS; do
    echo "  Deleting security group: $sg"
    # First remove all rules
    aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)" 2>/dev/null || true
    aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" 2>/dev/null || true
    aws ec2 delete-security-group --group-id "$sg" || true
  done
done

# 8. Delete NAT Gateways and wait
echo ""
echo "==> Step 8: Deleting NAT Gateways"
for vpc in $VPCS; do
  NAT_GWS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query 'NatGateways[*].NatGatewayId' --output text)
  for nat in $NAT_GWS; do
    echo "  Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat || true
  done
done

echo "  Waiting 90s for NAT Gateways to delete..."
sleep 90

# 9. Release Elastic IPs
echo ""
echo "==> Step 9: Releasing Elastic IPs"
EIPS=$(aws ec2 describe-addresses --query 'Addresses[*].AllocationId' --output text)
for eip in $EIPS; do
  echo "  Releasing EIP: $eip"
  aws ec2 release-address --allocation-id $eip 2>/dev/null || true
done

# 10. Delete Network Interfaces
echo ""
echo "==> Step 10: Deleting Network Interfaces"
for vpc in $VPCS; do
  ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" "Name=status,Values=available" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
  for eni in $ENIS; do
    echo "  Deleting ENI: $eni"
    aws ec2 delete-network-interface --network-interface-id $eni || true
  done
done

# 11. Delete VPCs
echo ""
echo "==> Step 11: Deleting VPCs"
WIZ_VPCS=$(aws ec2 describe-vpcs --query "Vpcs[?contains(Tags[?Key=='Name'].Value|[0], 'wiz')].VpcId" --output text)

for vpc in $WIZ_VPCS; do
  echo "  Deleting VPC: $vpc"
  
  # Delete Internet Gateways
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query 'InternetGateways[*].InternetGatewayId' --output text)
  for igw in $IGWS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null || true
  done
  
  # Delete Subnets
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[*].SubnetId' --output text)
  for subnet in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $subnet 2>/dev/null || true
  done
  
  # Delete Route Tables
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" "Name=association.main,Values=false" --query 'RouteTables[*].RouteTableId' --output text)
  for rt in $RTS; do
    aws ec2 delete-route-table --route-table-id $rt 2>/dev/null || true
  done
  
  # Delete VPC
  aws ec2 delete-vpc --vpc-id $vpc || true
done

# 12. Delete IAM Resources
echo ""
echo "==> Step 12: Deleting IAM Resources"

# Instance profile
if aws iam get-instance-profile --instance-profile-name "${PROJECT}-ec2-profile" 2>/dev/null; then
  echo "  Removing role from instance profile"
  aws iam remove-role-from-instance-profile --instance-profile-name "${PROJECT}-ec2-profile" --role-name "${PROJECT}-ec2-role" || true
  echo "  Deleting instance profile: ${PROJECT}-ec2-profile"
  aws iam delete-instance-profile --instance-profile-name "${PROJECT}-ec2-profile" || true
fi

# EC2 role
if aws iam get-role --role-name "${PROJECT}-ec2-role" 2>/dev/null; then
  echo "  Detaching policies from ${PROJECT}-ec2-role"
  aws iam detach-role-policy --role-name "${PROJECT}-ec2-role" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" || true
  
  # Delete inline policies
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "${PROJECT}-ec2-role" --query 'PolicyNames' --output text 2>/dev/null || echo "")
  for policy in $INLINE_POLICIES; do
    echo "  Deleting inline policy: $policy"
    aws iam delete-role-policy --role-name "${PROJECT}-ec2-role" --policy-name "$policy" || true
  done
  
  echo "  Deleting IAM role: ${PROJECT}-ec2-role"
  aws iam delete-role --role-name "${PROJECT}-ec2-role" || true
fi

# EKS node role (if exists)
for role in "${PROJECT}-ng-eks-node-group-"*; do
  if aws iam get-role --role-name "$role" 2>/dev/null; then
    echo "  Cleaning up EKS node role: $role"
    # Detach all managed policies
    POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $POLICIES; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" || true
    done
    aws iam delete-role --role-name "$role" || true
  fi
done

# 13. Delete CloudWatch Log Groups
echo ""
echo "==> Step 13: Deleting CloudWatch Log Groups"
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/${PROJECT}" --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
for lg in $LOG_GROUPS; do
  echo "  Deleting log group: $lg"
  aws logs delete-log-group --log-group-name "$lg" || true
done

# 14. Delete KMS Keys
echo ""
echo "==> Step 14: Scheduling KMS Key Deletion"
KMS_ALIASES=$(aws kms list-aliases --query "Aliases[?contains(AliasName, 'eks/${PROJECT}')].AliasName" --output text)
for alias in $KMS_ALIASES; do
  KEY_ID=$(aws kms list-aliases --query "Aliases[?AliasName=='$alias'].TargetKeyId" --output text)
  if [ -n "$KEY_ID" ]; then
    echo "  Deleting KMS alias: $alias"
    aws kms delete-alias --alias-name "$alias" || true
    echo "  Scheduling key deletion: $KEY_ID"
    aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 || true
  fi
done

# 15. Delete ECR Repositories
echo ""
echo "==> Step 15: Deleting ECR Repositories"
ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'wiz')].repositoryName" --output text 2>/dev/null || echo "")
for repo in $ECR_REPOS; do
  echo "  Force deleting ECR repository: $repo"
  aws ecr delete-repository --repository-name "$repo" --force || true
done

echo ""
echo "==> Complete Cleanup Finished! ✅"
echo ""
echo "Summary:"
aws ec2 describe-vpcs --query 'length(Vpcs)' --output text | xargs -I {} echo "  VPCs remaining: {}"
aws ec2 describe-addresses --query 'length(Addresses)' --output text | xargs -I {} echo "  Elastic IPs: {}"
echo ""
echo "You can now run: cd terraform && terraform init && terraform apply"
