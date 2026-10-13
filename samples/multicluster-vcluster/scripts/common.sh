#!/usr/bin/env bash

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

export AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-kedify-vcluster-kpa-demo}"
export RESOURCE_PREFIX="${RESOURCE_PREFIX:-kfyvcdemo}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-kedify-vcluster-kpa}"
export MAIN_NODE_COUNT="${MAIN_NODE_COUNT:-3}"
export MAIN_NODE_VM_SIZE="${MAIN_NODE_VM_SIZE:-Standard_D8s_v5}"
export MAIN_KUBERNETES_VERSION="${MAIN_KUBERNETES_VERSION:-1.35.8}"
export REDIS_NODE_COUNT="${REDIS_NODE_COUNT:-2}"
export REDIS_NODE_VM_SIZE="${REDIS_NODE_VM_SIZE:-Standard_D4s_v5}"
export NAMESPACE="${NAMESPACE:-keda}"
export AGENT_CHART="${AGENT_CHART:-kedify/kedify-agent}"
export AGENT_CHART_VERSION="${AGENT_CHART_VERSION:-v0.8.2}"

export MAIN_KUBECONFIG="${MAIN_KUBECONFIG:-${REPO_ROOT}/.kube/main.yaml}"
export REDIS_KUBECONFIG="${REDIS_KUBECONFIG:-${REPO_ROOT}/.kube/redis.yaml}"

require_command() {
  local command_name
  for command_name in "$@"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      echo "required command not found: ${command_name}" >&2
      exit 1
    fi
  done
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "required file not found: $1" >&2
    exit 1
  fi
}

require_env() {
  local variable_name
  for variable_name in "$@"; do
    if [[ -z "${!variable_name:-}" ]]; then
      echo "required environment variable not set: ${variable_name}" >&2
      echo "copy .env.example to .env and configure the Kedify credentials" >&2
      exit 1
    fi
  done
}

azure_output() {
  local output_name="$1"
  az deployment group show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${DEPLOYMENT_NAME}" \
    --query "properties.outputs.${output_name}.value" \
    --output tsv
}

ensure_azure_login() {
  if ! az account show >/dev/null 2>&1; then
    echo "Azure CLI is not logged in; run 'az login' first" >&2
    exit 1
  fi
}

