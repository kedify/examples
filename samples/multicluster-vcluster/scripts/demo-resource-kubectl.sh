#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
index="${1:?Pass the member index}"
shift
case "${index}" in 1|2|3) ;; *) echo 'Member must be 1, 2, or 3' >&2; exit 2 ;; esac
require_command kubectl vcluster
require_file "${MAIN_KUBECONFIG}"
# Each invocation fetches this incarnation's credentials. Command mode cleans
# up its proxy and temporary kubeconfig when kubectl exits. No host fallback.
exec env KUBECONFIG="${MAIN_KUBECONFIG}" vcluster connect "vc-${index}" \
  --namespace "vcluster-${index}" --background-proxy=false --silent -- kubectl "$@"
