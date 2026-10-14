#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"

pane="${1:-host}"
case "${pane}" in host|1|2|3) ;; *) echo 'Pane must be host, 1, 2, or 3' >&2; exit 2 ;; esac
require_command python3 kubectl
require_file "${MAIN_KUBECONFIG}"
umask 077
export DEMO_OBSERVER_DIR="${DEMO_OBSERVER_DIR:-${REPO_ROOT}/state/observer}"
mkdir -p "${DEMO_OBSERVER_DIR}"

if [[ "${pane}" == host ]]; then
  exec python3 "${REPO_ROOT}/scripts/demo-observer.py" host
fi

require_command vcluster
child_pid=''
cleanup() {
  if [[ -n "${child_pid}" ]]; then
    kill -TERM "${child_pid}" 2>/dev/null || true
    wait "${child_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

while true; do
  registration="$(registration_name_for_cluster "$(vcluster_cluster_name "${pane}")" 2>/dev/null || true)"
  ready=''
  if [[ -n "${registration}" ]]; then
    status="$(kubectl --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${NAMESPACE}" get "clusterregistration/${registration}" --output 'jsonpath={.status.conditions[?(@.type=="Ready")].status}:{.metadata.uid}' 2>/dev/null || true)"
    ready="${status%%:*}"
    export DEMO_REGISTRATION_UID="${status#*:}"
  fi
  if [[ "${ready}" != True ]]; then
    python3 "${REPO_ROOT}/scripts/demo-observer.py" waiting "${pane}"
    sleep "${DEMO_REFRESH_SECONDS:-3}"
    continue
  fi
  # Command mode gives the child a temporary kubeconfig. It does not switch the
  # presenter's default context. Separate ports also allow a control shell.
  KUBECONFIG="${MAIN_KUBECONFIG}" vcluster connect "$(vcluster_release_name "${pane}")" \
    --namespace "$(vcluster_namespace "${pane}")" \
    --background-proxy=false --silent --local-port "$((18440 + pane))" -- \
    python3 "${REPO_ROOT}/scripts/demo-observer.py" member "${pane}" 2>/dev/null &
  child_pid=$!
  wait "${child_pid}" || true
  child_pid=''
  sleep "${DEMO_REFRESH_SECONDS:-3}"
done
