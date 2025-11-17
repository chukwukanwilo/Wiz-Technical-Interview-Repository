#!/usr/bin/env bash
set -euo pipefail

# build_push.sh
# Build the Docker image from ./app and push to ECR.
# Requires AWS CLI configured and ECR repository already created.
# Environment variables used:
#   ECR_REGISTRY (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com)
#   ECR_REPO     (e.g. wiz-tasky)
#   IMAGE_TAG    (optional, default: latest)

IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "${ECR_REGISTRY:-}" || -z "${ECR_REPO:-}" ]]; then
  echo "ECR_REGISTRY and ECR_REPO must be set"
  exit 1
fi

FULL_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

echo "Building image ${FULL_IMAGE} from ./app"
cd "$(dirname "${BASH_SOURCE[0]}")/../app"
docker build -t "${FULL_IMAGE}" .

echo "Logging into ECR ${ECR_REGISTRY}"
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "Pushing ${FULL_IMAGE}"
# ensure the repo exists (helper will print repo URI)
echo "Ensuring ECR repo ${ECR_REPO} exists"
REPO_URI=$("$(dirname "${BASH_SOURCE[0]}")/create_ecr_repo.sh" "${ECR_REPO}" || true)
if [[ -n "$REPO_URI" ]]; then
  echo "Repo URI: $REPO_URI"
fi

docker push "${FULL_IMAGE}"

echo "Image pushed: ${FULL_IMAGE}"

echo "You can set IMAGE=${FULL_IMAGE} when running deploy.sh or Makefile targets"
