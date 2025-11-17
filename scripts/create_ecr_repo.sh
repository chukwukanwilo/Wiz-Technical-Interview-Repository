#!/usr/bin/env bash
set -euo pipefail

# create_ecr_repo.sh
# Creates an ECR repository if it doesn't exist and prints the repository URI.
# Usage:
#   create_ecr_repo.sh <repo-name> [region]
# Returns: prints full repo URI (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/repo)

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <repo-name> [region]" >&2
  exit 2
fi

REPO_NAME="$1"
REGION="${2:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"

set -x

# Check if repository exists
if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "ECR repository $REPO_NAME already exists in $REGION"
else
  echo "Creating ECR repository $REPO_NAME in $REGION"
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" >/dev/null
fi

# Get account id
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "$REPO_URI"

set +x
