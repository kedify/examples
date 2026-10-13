#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/presentation-common.sh"

require_command helm kubectl
require_file "${MAIN_KUBECONFIG}"

for index in 1 2; do
  wait_for_vcluster_registration "${index}"
done

third_cluster_name="$(vcluster_cluster_name 3)"
if [[ -n "$(registration_name_for_cluster "${third_cluster_name}")" ]]; then
  echo "${third_cluster_name} is already registered; run 'make reset-third-vcluster' before presenting its lifecycle" >&2
  exit 1
fi
if helm --kubeconfig "${MAIN_KUBECONFIG}" --namespace "$(vcluster_namespace 3)" status "$(vcluster_release_name 3)" >/dev/null 2>&1; then
  echo "the vc-3 Helm release already exists without a registration; run 'make reset-third-vcluster' and investigate before presenting" >&2
  exit 1
fi

echo
demo_heading 'Prepared state: two discovered vClusters are Ready'
show_vcluster_registrations
echo
demo_command 'make third-vcluster'
demo_note 'Agent bootstraps CRDs and registration. Central KEDA/KPA keep running.'

kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  get clusterregistrations.multicluster.kedify.io \
  --selector multicluster.kedify.io/managed-by=vcluster-discovery \
  --watch \
  --output-watch-events \
  --output custom-columns='EVENT:.type,NAME:.object.metadata.name,CLUSTER:.object.spec.clusterName,READY:.object.status.conditions[?(@.type=="Ready")].status,REASON:.object.status.conditions[?(@.type=="Ready")].reason' &
watch_pid=$!
cleanup_watch() {
  kill "${watch_pid}" >/dev/null 2>&1 || true
  wait "${watch_pid}" 2>/dev/null || true
}
trap cleanup_watch EXIT

install_vcluster 3
wait_for_vcluster_registration 3
sleep 2
cleanup_watch
trap - EXIT

registration_name="$(registration_name_for_cluster "${third_cluster_name}")"
echo
demo_ok 'Lifecycle complete: Agent bootstrapped vc-3; registration is Ready'
kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
  --namespace "${NAMESPACE}" \
  get "clusterregistration.multicluster.kedify.io/${registration_name}" \
  --output wide
echo
echo "All presentation clusters"
show_vcluster_registrations
echo
demo_note 'Next: make demo-workload, then make demo-queue-on'
