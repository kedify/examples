#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"

require_command helm kubectl
require_file "${MAIN_KUBECONFIG}"

echo "Installing the two vClusters that form the prepared demo baseline"
for index in 1 2; do
  install_vcluster "${index}"
  wait_for_vcluster_registration "${index}"
done

if [[ -n "$(registration_name_for_cluster "$(vcluster_cluster_name 3)")" ]]; then
  echo "warning: the third vCluster is already registered; run 'make reset-third-vcluster' before the presentation" >&2
fi

show_vcluster_registrations
