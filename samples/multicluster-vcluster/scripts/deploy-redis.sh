#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command kubectl openssl
require_file "${REDIS_KUBECONFIG}"

mkdir -p "${REPO_ROOT}/state"
password_file="${REPO_ROOT}/state/redis-password"
if [[ ! -s "${password_file}" ]]; then
  openssl rand -hex 24 >"${password_file}"
  chmod 600 "${password_file}"
fi
redis_password="$(<"${password_file}")"

kubectl --kubeconfig "${REDIS_KUBECONFIG}" apply -f "${REPO_ROOT}/manifests/redis/redis.yaml" --prune=false
kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis create secret generic redis-auth \
  --from-literal=password="${redis_password}" \
  --dry-run=client \
  --output yaml | kubectl --kubeconfig "${REDIS_KUBECONFIG}" apply -f -
kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis rollout restart deployment/redis
kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis rollout status deployment/redis --timeout=5m
kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis wait service/redis \
  --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  --timeout=10m

redis_ip="$(kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis get service redis --output jsonpath='{.status.loadBalancer.ingress[0].ip}')"
printf '%s\n' "${redis_ip}" >"${REPO_ROOT}/state/redis-ip"
echo "Redis is reachable inside the demo VNet at ${redis_ip}:6379"

