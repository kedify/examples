#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command az
ensure_azure_login

mkdir -p "${REPO_ROOT}/.kube"
main_cluster="$(azure_output mainClusterName)"
redis_cluster="$(azure_output redisClusterName)"

az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${main_cluster}" \
  --file "${MAIN_KUBECONFIG}" \
  --overwrite-existing

az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${redis_cluster}" \
  --file "${REDIS_KUBECONFIG}" \
  --overwrite-existing

chmod 600 "${MAIN_KUBECONFIG}" "${REDIS_KUBECONFIG}"

