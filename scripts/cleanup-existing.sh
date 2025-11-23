#!/usr/bin/env bash
set -euo pipefail

# cleanup-existing.sh
# Manually destroy conflicting resources from previous runs

REGION="us-east-1"

echo "==> Cleaning up existing resources..."

# Delete CloudTrail
if aws cloudtrail describe-trails --query "trailList[?Name=='wiz-exercise-trail'].Name" --output text | grep -q "wiz-exercise-trail"; then
  echo "Deleting CloudTrail: wiz-exercise-trail"
  aws cloudtrail delete-trail --name wiz-exercise-trail --region $REGION || true
fi

# Delete KMS alias
if aws kms list-aliases --query "Aliases[?AliasName=='alias/eks/wiz-exercise-eks'].AliasName" --output text | grep -q "alias/eks/wiz-exercise-eks"; then
  echo "Deleting KMS alias: alias/eks/wiz-exercise-eks"
  KEY_ID=$(aws kms list-aliases --query "Aliases[?AliasName=='alias/eks/wiz-exercise-eks'].TargetKeyId" --output text)
  if [ -n "$KEY_ID" ]; then
    aws kms delete-alias --alias-name alias/eks/wiz-exercise-eks --region $REGION || true
    echo "Scheduling KMS key deletion: $KEY_ID"
    aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 --region $REGION || true
  fi
fi

# Delete CloudWatch Log Group
if aws logs describe-log-groups --log-group-name-prefix /aws/eks/wiz-exercise-eks/cluster --region $REGION --query 'logGroups[0].logGroupName' --output text | grep -q "/aws/eks/wiz-exercise-eks/cluster"; then
  echo "Deleting CloudWatch Log Group: /aws/eks/wiz-exercise-eks/cluster"
  aws logs delete-log-group --log-group-name /aws/eks/wiz-exercise-eks/cluster --region $REGION || true
fi

# Delete IAM instance profile and role
if aws iam get-instance-profile --instance-profile-name wiz-exercise-ec2-profile 2>/dev/null; then
  echo "Deleting IAM instance profile: wiz-exercise-ec2-profile"
  aws iam remove-role-from-instance-profile --instance-profile-name wiz-exercise-ec2-profile --role-name wiz-exercise-ec2-role || true
  aws iam delete-instance-profile --instance-profile-name wiz-exercise-ec2-profile || true
fi

if aws iam get-role --role-name wiz-exercise-ec2-role 2>/dev/null; then
  echo "Detaching policies from IAM role: wiz-exercise-ec2-role"
  aws iam detach-role-policy --role-name wiz-exercise-ec2-role --policy-arn arn:aws:iam::aws:policy/AdministratorAccess || true
  echo "Deleting IAM role: wiz-exercise-ec2-role"
  aws iam delete-role --role-name wiz-exercise-ec2-role || true
fi

echo "==> Cleanup complete!"
echo "Now you can run: cd terraform && terraform apply"
