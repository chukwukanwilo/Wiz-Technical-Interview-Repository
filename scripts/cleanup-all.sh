#!/usr/bin/env bash
set -euo pipefail

# cleanup-all.sh
# Delete old EKS clusters and VPCs to free up account limits

REGION="us-east-1"

echo "==> Comprehensive AWS Cleanup Script"
echo ""

# Function to wait for node group deletion
wait_for_nodegroup_deletion() {
  local cluster=$1
  local nodegroup=$2
  echo "Waiting for node group $nodegroup in cluster $cluster to delete..."
  
  while true; do
    STATUS=$(aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$nodegroup" --query 'nodegroup.status' --output text 2>/dev/null || echo "DELETED")
    
    if [ "$STATUS" == "DELETED" ]; then
      echo "✓ Node group $nodegroup deleted"
      break
    fi
    
    echo "  Status: $STATUS ... waiting 30s"
    sleep 30
  done
}

# Function to wait for cluster deletion
wait_for_cluster_deletion() {
  local cluster=$1
  echo "Waiting for cluster $cluster to delete..."
  
  while true; do
    STATUS=$(aws eks describe-cluster --name "$cluster" --query 'cluster.status' --output text 2>/dev/null || echo "DELETED")
    
    if [ "$STATUS" == "DELETED" ]; then
      echo "✓ Cluster $cluster deleted"
      break
    fi
    
    echo "  Status: $STATUS ... waiting 30s"
    sleep 30
  done
}

# 1. Wait for node groups to finish deleting (already triggered)
echo ""
echo "==> Step 1: Waiting for node groups to delete"
wait_for_nodegroup_deletion "wiz-exercise-eks" "wiz-exercise-ng-20251123204829056900000014" || true
wait_for_nodegroup_deletion "my-wiz-test-assessment-cluster" "wiz" || true

# 2. Delete EKS clusters
echo ""
echo "==> Step 2: Deleting EKS clusters"

if aws eks describe-cluster --name wiz-exercise-eks &>/dev/null; then
  echo "Deleting cluster: wiz-exercise-eks"
  aws eks delete-cluster --name wiz-exercise-eks --region $REGION
  wait_for_cluster_deletion "wiz-exercise-eks"
else
  echo "✓ Cluster wiz-exercise-eks already deleted"
fi

if aws eks describe-cluster --name my-wiz-test-assessment-cluster &>/dev/null; then
  echo "Deleting cluster: my-wiz-test-assessment-cluster"
  aws eks delete-cluster --name my-wiz-test-assessment-cluster --region $REGION
  wait_for_cluster_deletion "my-wiz-test-assessment-cluster"
else
  echo "✓ Cluster my-wiz-test-assessment-cluster already deleted"
fi

# 3. Delete old VPC (eksctl-created one)
echo ""
echo "==> Step 3: Deleting old VPC resources"

OLD_VPC="vpc-03aa0115a8cf3c67e"  # eksctl VPC

if aws ec2 describe-vpcs --vpc-ids $OLD_VPC &>/dev/null; then
  echo "Deleting VPC: $OLD_VPC"
  
  # Delete NAT Gateways first
  echo "  Deleting NAT Gateways..."
  NAT_GWS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$OLD_VPC" --query 'NatGateways[*].NatGatewayId' --output text)
  for nat in $NAT_GWS; do
    echo "    Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat || true
  done
  
  # Wait for NAT gateways to delete
  echo "  Waiting for NAT Gateways to delete (this may take a few minutes)..."
  sleep 60
  
  # Delete Internet Gateway
  echo "  Deleting Internet Gateways..."
  IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$OLD_VPC" --query 'InternetGateways[*].InternetGatewayId' --output text)
  if [ -n "$IGW" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $OLD_VPC || true
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW || true
  fi
  
  # Delete subnets
  echo "  Deleting Subnets..."
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$OLD_VPC" --query 'Subnets[*].SubnetId' --output text)
  for subnet in $SUBNETS; do
    echo "    Deleting subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet || true
  done
  
  # Delete route tables
  echo "  Deleting Route Tables..."
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$OLD_VPC" "Name=association.main,Values=false" --query 'RouteTables[*].RouteTableId' --output text)
  for rt in $RTS; do
    echo "    Deleting route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt || true
  done
  
  # Delete security groups (except default)
  echo "  Deleting Security Groups..."
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$OLD_VPC" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
  for sg in $SGS; do
    echo "    Deleting security group: $sg"
    aws ec2 delete-security-group --group-id $sg || true
  done
  
  # Finally delete VPC
  echo "  Deleting VPC: $OLD_VPC"
  aws ec2 delete-vpc --vpc-id $OLD_VPC || true
  echo "✓ VPC deleted"
else
  echo "✓ VPC $OLD_VPC already deleted"
fi

# 4. Release unused Elastic IPs
echo ""
echo "==> Step 4: Checking for unused Elastic IPs"
UNUSED_EIPS=$(aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId' --output text)
if [ -n "$UNUSED_EIPS" ]; then
  echo "Found unused EIPs: $UNUSED_EIPS"
  for eip in $UNUSED_EIPS; do
    echo "  Releasing EIP: $eip"
    aws ec2 release-address --allocation-id $eip || true
  done
else
  echo "✓ No unused EIPs found"
fi

echo ""
echo "==> Cleanup complete! ✅"
echo "You can now run terraform apply"
