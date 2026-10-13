#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command kubectl openssl
require_file "${REDIS_KUBECONFIG}"

umask 077
mkdir -p "${REPO_ROOT}/state"

password_file="${REPO_ROOT}/state/redis-password"
ip_file="${REPO_ROOT}/state/redis-ip"
password_tmp="$(mktemp "${REPO_ROOT}/state/.redis-password.XXXXXX")"
ip_tmp="$(mktemp "${REPO_ROOT}/state/.redis-ip.XXXXXX")"

cleanup() {
  rm -f "${password_tmp}" "${ip_tmp}"
}
trap cleanup EXIT

encoded_password="$(kubectl --kubeconfig "${REDIS_KUBECONFIG}" \
  --namespace redis get secret redis-auth \
  --output jsonpath='{.data.password}')"
if [[ -z "${encoded_password}" ]]; then
  echo "redis-auth Secret does not contain a password" >&2
  exit 1
fi
printf '%s' "${encoded_password}" | openssl base64 -d -A >"${password_tmp}"

redis_ip="$(kubectl --kubeconfig "${REDIS_KUBECONFIG}" \
  --namespace redis get service redis \
  --output jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if [[ -z "${redis_ip}" ]]; then
  echo "Redis Service does not have an internal load-balancer IP" >&2
  exit 1
fi
printf '%s\n' "${redis_ip}" >"${ip_tmp}"

mv "${password_tmp}" "${password_file}"
mv "${ip_tmp}" "${ip_file}"
chmod 600 "${password_file}" "${ip_file}"
trap - EXIT

echo "Recovered Redis connection state from the existing cluster."
echo "Redis endpoint: ${redis_ip}:6379"
echo "The Redis password was written to state/redis-password and was not printed."
