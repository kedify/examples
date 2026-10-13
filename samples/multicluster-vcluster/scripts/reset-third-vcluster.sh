#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"

require_command helm kubectl
require_file "${MAIN_KUBECONFIG}"

name="$(vcluster_release_name 3)"
namespace="$(vcluster_namespace 3)"
cluster_name="$(vcluster_cluster_name 3)"

if helm --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${namespace}" status "${name}" >/dev/null 2>&1; then
  helm --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${namespace}" uninstall "${name}" --wait
fi
kubectl --kubeconfig "${MAIN_KUBECONFIG}" delete namespace "${namespace}" --ignore-not-found --wait=true

deadline=$((SECONDS + ${VCLUSTER_REGISTRATION_TIMEOUT_SECONDS:-600}))
while ((SECONDS < deadline)); do
  if [[ -z "$(registration_name_for_cluster "${cluster_name}")" ]]; then
    echo "vc-3 and its generated registration have been removed; the two-cluster baseline is ready"
    show_vcluster_registrations
    exit 0
  fi
  sleep 2
done

echo "timed out waiting for the generated registration for ${cluster_name} to be removed" >&2
exit 1
