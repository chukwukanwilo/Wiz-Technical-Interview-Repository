#!/usr/bin/env bash
set -euo pipefail

# smoke_test.sh
# Simple smoke tests for the `tasky` app.
# Requirements: kubectl configured (KUBECONFIG env) and access to the cluster.
# It will port-forward the service `tasky-svc` and curl two endpoints.

PORT_FORWARD_LOCAL=8080
SERVICE_NAME=tasky-svc
NAMESPACE=default
TIMEOUT=${SMOKE_TIMEOUT:-120}

echo "Waiting for deployment rollout..."
kubectl rollout status deployment/tasky-app -n ${NAMESPACE} --timeout=120s || true

echo "Port-forwarding ${SERVICE_NAME} to localhost:${PORT_FORWARD_LOCAL}"
kubectl port-forward svc/${SERVICE_NAME} ${PORT_FORWARD_LOCAL}:80 -n ${NAMESPACE} >/dev/null 2>&1 &
PF_PID=$!
# give port-forward a moment
sleep 2

trap 'echo "Cleaning up..."; kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

set +e
HTTP_STATUS_ROOT=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${PORT_FORWARD_LOCAL}/)
HTTP_STATUS_WIZ=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${PORT_FORWARD_LOCAL}/wiz-file)
HTTP_BODY_WIZ=$(curl -s http://127.0.0.1:${PORT_FORWARD_LOCAL}/wiz-file || true)
HTTP_STATUS_TODOS=$(curl -s -o /dev/null -w "%{http_code}" -X GET http://127.0.0.1:${PORT_FORWARD_LOCAL}/todos)
set -e

echo "/ -> HTTP ${HTTP_STATUS_ROOT}"
echo "/wiz-file -> HTTP ${HTTP_STATUS_WIZ}"
echo "body: ${HTTP_BODY_WIZ}"
echo "/todos -> HTTP ${HTTP_STATUS_TODOS}"

if [[ "${HTTP_STATUS_ROOT}" != "200" || "${HTTP_STATUS_WIZ}" != "200" ]]; then
  echo "Smoke tests failed: endpoints did not return 200" >&2
  exit 2
fi

echo "Smoke tests passed"
