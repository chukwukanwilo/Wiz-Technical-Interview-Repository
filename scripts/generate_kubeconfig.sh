#!/usr/bin/env bash
set -euo pipefail

# generate_kubeconfig.sh
# Uses terraform outputs to write a kubeconfig file to ./kubeconfig
# and exports KUBECONFIG when sourcing this script.

TF_DIR="$(dirname "${BASH_SOURCE[0]}")/../terraform"
OUT_KUBECONFIG="$(pwd)/kubeconfig"

cd "${TF_DIR}"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not found in PATH" >&2
  exit 1
fi

echo "==> Exporting kubeconfig from Terraform output to ${OUT_KUBECONFIG}"
terraform output -raw kubeconfig > "${OUT_KUBECONFIG}"

echo "Wrote kubeconfig file. To use it run:\n  export KUBECONFIG=${OUT_KUBECONFIG}"
