#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/presentation-common.sh"

mode="${1:-deployments}"
pane="${2:-host}"
case "${mode}" in deployments|resources) ;; *) echo 'Mode must be deployments or resources' >&2; exit 2 ;; esac
case "${pane}" in host|1|2|3) ;; *) echo 'Pane must be host, 1, 2, or 3' >&2; exit 2 ;; esac
require_command kubectl
require_file "${MAIN_KUBECONFIG}"
if [[ "${mode}" == deployments ]]; then require_command watch; else require_command zsh; fi

if [[ "${pane}" == host ]]; then
  unset DEMO_RESOURCE_MEMBER
  export KUBECONFIG="${MAIN_KUBECONFIG}"
  exec "${REPO_ROOT}/scripts/demo-cluster-session.sh" "${mode}" HOST
fi

require_command vcluster
# Deployment watches coexist with observers (18441-18443). Resource-shell
# commands connect on demand with a fresh kubeconfig and a random free port.
port_base=18540
child_pid=''
cleanup() {
  if [[ -n "${child_pid}" ]]; then
    kill -TERM "${child_pid}" 2>/dev/null || true
    wait "${child_pid}" 2>/dev/null || true
    child_pid=''
  fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

while true; do
  registration="$(registration_name_for_cluster "$(vcluster_cluster_name "${pane}")" 2>/dev/null || true)"
  ready=''
  registration_state=''
  if [[ -n "${registration}" ]]; then
    registration_state="$(kubectl --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${NAMESPACE}" \
      get "clusterregistration/${registration}" \
      --output 'jsonpath={.status.conditions[?(@.type=="Ready")].status}:{.metadata.uid}' 2>/dev/null || true)"
    ready="${registration_state%%:*}"
  fi
  if [[ "${ready}" != True ]]; then
    if [[ -t 1 ]]; then printf '\033[H\033[J'; fi
    demo_heading "vc-${pane} / waiting for registration"
    demo_note "Create vc-${pane} from your command pane. This pane connects when Ready."
    sleep "${DEMO_REFRESH_SECONDS:-3}"
    continue
  fi
  if [[ "${mode}" == resources ]]; then
    export KUBECONFIG="${MAIN_KUBECONFIG}"
    export DEMO_RESOURCE_MEMBER="${pane}"
    exec "${REPO_ROOT}/scripts/demo-cluster-session.sh" resources "vc-${pane}"
  fi
  KUBECONFIG="${MAIN_KUBECONFIG}" vcluster connect "$(vcluster_release_name "${pane}")" \
    --namespace "$(vcluster_namespace "${pane}")" \
    --background-proxy=false --silent --local-port "$((port_base + pane))" -- \
    "${REPO_ROOT}/scripts/demo-cluster-session.sh" deployments "vc-${pane}" < /dev/tty &
  child_pid=$!
  # watch itself keeps running after a failed kubectl read. Monitor identity
  # independently so removing/recreating a tenant replaces that stale proxy.
  while kill -0 "${child_pid}" 2>/dev/null; do
    current_registration_state="$(kubectl --kubeconfig "${MAIN_KUBECONFIG}" --namespace "${NAMESPACE}" \
      get "clusterregistration/${registration}" \
      --output 'jsonpath={.status.conditions[?(@.type=="Ready")].status}:{.metadata.uid}' 2>/dev/null || true)"
    if [[ "${current_registration_state}" != "${registration_state}" ]]; then
      cleanup
      break
    fi
    sleep "${DEMO_REFRESH_SECONDS:-3}"
  done
  if [[ -n "${child_pid}" ]]; then wait "${child_pid}" || true; child_pid=''; fi
  sleep "${DEMO_REFRESH_SECONDS:-3}"
done
