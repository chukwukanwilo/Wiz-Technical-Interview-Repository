#!/usr/bin/env bash
set -euo pipefail

# deploy.sh
# 1) Reads Terraform outputs (mongo_private_ip, kubeconfig)
# 2) Patches k8s/deployment.yaml replacing <EC2_PRIVATE_IP> with the private IP
#    and replacing <REGISTRY> with the provided image registry (or IMAGE env var)
# 3) Applies k8s manifests (kubectl apply)

# Usage:
#   IMAGE=<registry>/<repo>:tag ./scripts/deploy.sh
# or set ECR_REGISTRY/ECR_REPO and IMAGE_TAG

# Locate repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/k8s"

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

# Ensure terraform is available
if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required but not found in PATH" >&2
  exit 1
fi

cd "$TF_DIR"

# get mongo private ip
echo "==> Getting mongo_private_ip from Terraform outputs"
MONGO_IP=$(terraform output -raw mongo_private_ip)
if [[ -z "$MONGO_IP" ]]; then
  echo "mongo_private_ip output is empty" >&2
  exit 1
fi

echo "mongo private ip: $MONGO_IP"

# get kubeconfig
KUBECONFIG_PATH="$ROOT_DIR/kubeconfig"
terraform output -raw kubeconfig > "$KUBECONFIG_PATH"
export KUBECONFIG="$KUBECONFIG_PATH"

echo "Wrote kubeconfig to $KUBECONFIG_PATH"

# Prepare a patched copy of k8s/deployment.yaml
PATCHED="$ROOT_DIR/k8s/deployment-patched.yaml"
cp "$K8S_DIR/deployment.yaml" "$PATCHED"

# replace placeholders
sed -i.bak "s~<EC2_PRIVATE_IP>~${MONGO_IP}~g" "$PATCHED"
# replace registry placeholder if present
REG_PLACEHOLDER="<REGISTRY>"
if grep -q "$REG_PLACEHOLDER" "$PATCHED"; then
  # prefer full IMAGE (including registry/repo), or just registry part
  # if IMAGE contains '/': use it directly, otherwise hope it's full
  sed -i.bak "s~${REG_PLACEHOLDER}~${IMAGE_TO_DEPLOY%/*}~g" "$PATCHED"
fi

# Also set the image on the deployment directly with kubectl (safer)
DEPLOYMENT_NAME="tasky-app"
CONTAINER_NAME="tasky"

# Apply manifests
echo "==> Applying k8s manifests"
kubectl apply -f "$PATCHED"

# Force-set the image on the deployment
echo "==> Setting deployment image to ${IMAGE_TO_DEPLOY}"
kubectl set image deployment/${DEPLOYMENT_NAME} ${CONTAINER_NAME}=${IMAGE_TO_DEPLOY} --record || true

# Clean up backups created by sed on macOS and Linux
rm -f "$PATCHED.bak"

echo "Deployment complete. Check pods with: kubectl get pods -l app=tasky"
