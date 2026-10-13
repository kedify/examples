#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"

require_command kubectl
require_file "${MAIN_KUBECONFIG}"
require_file "${REDIS_KUBECONFIG}"

kubectl --kubeconfig "${MAIN_KUBECONFIG}" get nodes
kubectl --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${NAMESPACE}" get deployments,pods
expected_vclusters="${EXPECTED_VCLUSTERS:-2}"
for ((index = 1; index <= expected_vclusters; index++)); do
  wait_for_vcluster_registration "${index}"
done

actual_vclusters="$(vcluster_registration_count)"
if [[ "${actual_vclusters}" != "${expected_vclusters}" ]]; then
  echo "expected ${expected_vclusters} discovered vClusters, found ${actual_vclusters}" >&2
  show_vcluster_registrations >&2
  exit 1
fi
show_vcluster_registrations
kubectl --kubeconfig "${REDIS_KUBECONFIG}" --namespace redis get deployment,pod,service
