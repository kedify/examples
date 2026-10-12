#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command az
ensure_azure_login

az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${AZURE_LOCATION}" \
  --output none

az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${REPO_ROOT}/infra/main.bicep" \
  --parameters \
    location="${AZURE_LOCATION}" \
    resourcePrefix="${RESOURCE_PREFIX}" \
    mainNodeCount="${MAIN_NODE_COUNT}" \
    mainNodeVMSize="${MAIN_NODE_VM_SIZE}" \
    mainKubernetesVersion="${MAIN_KUBERNETES_VERSION}" \
    redisNodeCount="${REDIS_NODE_COUNT}" \
    redisNodeVMSize="${REDIS_NODE_VM_SIZE}" \
  --output table

"${REPO_ROOT}/scripts/get-credentials.sh"

main_cluster="$(azure_output mainClusterName)"
redis_cluster="$(azure_output redisClusterName)"

echo "Azure infrastructure is ready."
echo "Main cluster:  ${main_cluster} (${MAIN_NODE_COUNT} x ${MAIN_NODE_VM_SIZE})"
echo "Redis cluster: ${redis_cluster} (${REDIS_NODE_COUNT} x ${REDIS_NODE_VM_SIZE})"

