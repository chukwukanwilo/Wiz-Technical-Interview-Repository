#!/usr/bin/env bash
set -euo pipefail

# deploy.sh
# Deploys the tasky-app to EKS using Helm
# Prerequisites:
# - kubectl configured (aws eks update-kubeconfig already run)
# - MongoDB secret already created in the cluster
# - Helm installed

# Usage:
#   IMAGE=<registry>/<repo>:tag ./scripts/deploy.sh
# or set ECR_REGISTRY/ECR_REPO and IMAGE_TAG

# Locate repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_DIR="$ROOT_DIR/helm/tasky-app"

# Determine image
if [[ -n "${IMAGE:-}" ]]; then
  IMAGE_TO_DEPLOY="$IMAGE"
else
  if [[ -n "${ECR_REGISTRY:-}" && -n "${ECR_REPO:-}" ]]; then
    IMAGE_TAG="${IMAGE_TAG:-latest}"
    IMAGE_TO_DEPLOY="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
  else
    echo "Set IMAGE or (ECR_REGISTRY and ECR_REPO) environment variables." >&2
    exit 1
  fi
fi

# Extract repository and tag from image
IMAGE_REPO="${IMAGE_TO_DEPLOY%:*}"
IMAGE_TAG="${IMAGE_TO_DEPLOY##*:}"

echo "==> Deploying tasky-app with Helm"
echo "Image: ${IMAGE_TO_DEPLOY}"

# Check if MongoDB secret exists
if ! kubectl get secret mongodb-credentials &>/dev/null; then
  echo "WARNING: mongodb-credentials secret not found!"
  echo "Create it with: kubectl create secret generic mongodb-credentials --from-literal=MONGO_URI='mongodb://admin:password@<MONGO_IP>:27017/tasky?authSource=admin'"
fi

# Deploy using Helm
helm upgrade --install tasky-app "${HELM_DIR}" \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --wait \
  --timeout 5m

echo "==> Deployment complete!"
echo "Check status with:"
echo "  kubectl get pods -l app.kubernetes.io/name=tasky-app"
echo "  kubectl get ingress"
