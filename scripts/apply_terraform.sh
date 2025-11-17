#!/usr/bin/env bash
set -euo pipefail

# apply_terraform.sh
# Simple wrapper to init and apply Terraform in ./terraform
# Usage:
#   ./scripts/apply_terraform.sh [--auto-approve] [--var "key_name=my-key"]

cd "$(dirname "${BASH_SOURCE[0]}")/../terraform"

echo "==> Terraform init"
terraform init

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-approve)
      ARGS+=("-auto-approve")
      shift
      ;;
    --var)
      ARGS+=("-var")
      ARGS+=("$2")
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

echo "==> Terraform validate"
terraform validate

echo "==> Terraform plan"
terraform plan -out=tfplan "${ARGS[@]}"

if [[ " ${ARGS[*]} " == *" -auto-approve " ]]; then
  echo "==> Terraform apply (auto-approve)"
  terraform apply -auto-approve tfplan
else
  echo "==> To apply run: terraform apply tfplan or re-run this script with --auto-approve"
fi
