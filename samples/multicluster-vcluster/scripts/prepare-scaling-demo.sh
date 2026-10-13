#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/scaling-common.sh"

require_scaling_state

for index in 1 2; do
  wait_for_vcluster_registration "${index}"
done

echo "Verifying that workloads in the main AKS cluster can reach private Redis"
verify_main_to_redis_connectivity
echo "Verifying that vc-1 exposes PodMetrics for CPU scaling"
wait_for_remote_metrics_api 1
clear_demo_queues

echo "Preparing the vc-1 CPU Resource ScaledObject"
deploy_remote_cpu_scaledobject 1
wait_for_remote_resource 1 "kedifypodautoscaler.autoscaling.kedify.io/worker-autoscaler"
wait_for_deployment_replicas 1 1

echo "Preparing the vc-2 authenticated remote ScaledJob"
deploy_remote_scaledjob 2 "${VC2_QUEUE}"
wait_for_remote_resource 2 "scaledjob.keda.sh/worker"
vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" delete jobs \
  --selector scaledjob.keda.sh/name=worker \
  --ignore-not-found

echo
echo "Prepared remote-scaling state"
show_remote_scaledobject 1
show_remote_scaledjob 2
echo
echo "CPU load is disabled and Redis queues are empty. Create vc-3 during the presentation with 'make third-vcluster'."
