#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/scaling-common.sh"

require_scaling_state
clear_demo_queues

for index in 1 2 3; do
  if [[ -n "$(registration_name_for_cluster "$(vcluster_cluster_name "${index}")")" ]]; then
    vcluster_kubectl "${index}" delete namespace "${DEMO_NAMESPACE}" --ignore-not-found --wait=true
  fi
done

echo "Remote demo resources and Redis queues have been removed"
