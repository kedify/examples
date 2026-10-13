#!/usr/bin/env bash

set -euo pipefail
demo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "${demo_root}/scripts/presentation-common.sh"

mode="${1:?Pass deployments or resources}"
label="${2:?Pass the cluster label}"
case "${mode}" in
  deployments)
    export FORCE_COLOR=1
    exec watch --color --no-title --interval="${DEMO_REFRESH_SECONDS:-2}" --exec \
      "${demo_root}/scripts/demo-deployments.sh" "${label}"
    ;;
  resources)
    export DEMO_RESOURCE_LABEL="${label}"
    export DEMO_RESOURCE_HELPER="${demo_root}/scripts/demo-resource-kubectl.sh"
    demo_heading "${label} / interactive kubectl"
    if [[ "${label}" == HOST ]]; then
      demo_note 'kubectl uses the host kubeconfig in this pane.'
    else
      demo_note 'kubectl reconnects to this tenant for every command, including after recreation.'
    fi
    demo_command 'kubectl get scaledobject,scaledjob --all-namespaces'
    if [[ "${label}" == HOST ]]; then
      kubectl get scaledobject,scaledjob --all-namespaces || true
      printf '\nTry: kubectl -n keda get clusterregistrations\n\n'
    else
      "${DEMO_RESOURCE_HELPER}" "${DEMO_RESOURCE_MEMBER}" get scaledobject,scaledjob --all-namespaces || true
      printf '\nTry: kubectl -n demo-scaling get scaledobject,scaledjob,kpa\n\n'
    fi
    # Only this process uses the bundled zshrc. The kubectl function affects
    # typed commands; subprocesses and the user's usual PATH stay unchanged.
    exec env ZDOTDIR="${demo_root}/scripts/demo-zsh" zsh -d -i
    ;;
  *) printf 'Mode must be deployments or resources\n' >&2; exit 2 ;;
esac
