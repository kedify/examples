#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command helm kubectl
require_file "${MAIN_KUBECONFIG}"
require_env KEDIFY_ORG_ID KEDIFY_API_KEY KEDIFY_CLUSTER_NAME

helm repo add kedify https://kedify.github.io/charts --force-update
helm repo update kedify

helm upgrade --install kedify-agent "${AGENT_CHART}" \
  --server-side=false \
  --version "${AGENT_CHART_VERSION}" \
  --kubeconfig "${MAIN_KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set-string clusterName="${KEDIFY_CLUSTER_NAME}" \
  --set-string agent.agentId="${KEDIFY_AGENT_ID:-}" \
  --set-string agent.orgId="${KEDIFY_ORG_ID}" \
  --set-string agent.apiKey="${KEDIFY_API_KEY}" \
  --set global.features.multicluster.enabled=true \
  --set global.features.multicluster.type=dedicated \
  --set global.features.multicluster.vClusterDiscoveryEnabled=true \
  --set global.features.kedifyPodAutoscalerEnabled=true \
  --set keda.enabled=true \
  --set kpa.enabled=true \
  --wait \
  --timeout 10m

kubectl --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${NAMESPACE}" get deployments,pods
