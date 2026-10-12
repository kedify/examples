#!/usr/bin/env bash

# Shared functions for installing vClusters and observing their generated
# ClusterRegistration resources during the demo.

vcluster_release_name() {
  printf 'vc-%s' "$1"
}

vcluster_namespace() {
  printf 'vcluster-%s' "$1"
}

vcluster_cluster_name() {
  printf 'vc-%s.vcluster-%s' "$1" "$1"
}

install_vcluster() {
  local index="$1"
  local name
  local namespace
  name="$(vcluster_release_name "${index}")"
  namespace="$(vcluster_namespace "${index}")"

  helm upgrade --install "${name}" vcluster \
    --kubeconfig "${MAIN_KUBECONFIG}" \
    --repo https://charts.loft.sh \
    --version "${VCLUSTER_CHART_VERSION:-0.36.0}" \
    --namespace "${namespace}" \
    --create-namespace \
    --values "${REPO_ROOT}/values/vcluster.yaml" \
    --wait \
    --timeout 10m
}

registration_name_for_cluster() {
  local cluster_name="$1"
  kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
    --namespace "${NAMESPACE}" \
    get clusterregistrations.multicluster.kedify.io \
    --selector multicluster.kedify.io/managed-by=vcluster-discovery \
    --output "jsonpath={.items[?(@.spec.clusterName==\"${cluster_name}\")].metadata.name}"
}

wait_for_vcluster_registration() {
  local index="$1"
  local cluster_name
  local registration_name=""
  local deadline=$((SECONDS + ${VCLUSTER_REGISTRATION_TIMEOUT_SECONDS:-600}))
  cluster_name="$(vcluster_cluster_name "${index}")"

  echo "Waiting for discovery of vCluster ${cluster_name}"
  while ((SECONDS < deadline)); do
    registration_name="$(registration_name_for_cluster "${cluster_name}")"
    if [[ -n "${registration_name}" ]]; then
      kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
        --namespace "${NAMESPACE}" \
        wait "clusterregistration.multicluster.kedify.io/${registration_name}" \
        --for=condition=Ready \
        --timeout=10m
      return
    fi
    sleep 2
  done

  echo "timed out waiting for ClusterRegistration for ${cluster_name}" >&2
  return 1
}

vcluster_registration_count() {
  local names
  names="$(kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
    --namespace "${NAMESPACE}" \
    get clusterregistrations.multicluster.kedify.io \
    --selector multicluster.kedify.io/managed-by=vcluster-discovery \
    --output 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}')"
  if [[ -z "${names}" ]]; then
    printf '0'
  else
    printf '%s\n' "${names}" | wc -l
  fi
}

show_vcluster_registrations() {
  kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
    --namespace "${NAMESPACE}" \
    get clusterregistrations.multicluster.kedify.io \
    --selector multicluster.kedify.io/managed-by=vcluster-discovery \
    --output custom-columns='NAME:.metadata.name,PROVIDER:.spec.provider,CLUSTER:.spec.clusterName,READY:.status.conditions[?(@.type=="Ready")].status,REASON:.status.conditions[?(@.type=="Ready")].reason'
}

vcluster_kubectl() {
  local index="$1"
  shift
  KUBECONFIG="${MAIN_KUBECONFIG}" vcluster connect "$(vcluster_release_name "${index}")" \
    --namespace "$(vcluster_namespace "${index}")" \
    --background-proxy=false \
    --silent \
    -- kubectl "$@"
}
