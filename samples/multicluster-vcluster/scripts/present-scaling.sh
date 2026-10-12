#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/scaling-common.sh"

require_scaling_state

for index in 1 2 3; do
  wait_for_vcluster_registration "${index}"
done

vcluster_kubectl 1 --namespace "${DEMO_NAMESPACE}" get scaledobject.keda.sh/worker >/dev/null
vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" get scaledjob.keda.sh/worker >/dev/null

echo "Creating a remote ScaledObject in the newly registered vc-3"
deploy_remote_scaledobject 3 "${VC3_QUEUE}"
wait_for_remote_resource 3 "kedifypodautoscaler.autoscaling.kedify.io/worker-autoscaler"
wait_for_deployment_replicas 3 0
show_remote_scaledobject 3

clear_demo_queues
echo
echo "Adding Redis load for all three remote clusters"
echo "vc-1 queue length: $(push_queue_items "${VC1_QUEUE}" 6)"
echo "vc-2 queue length: $(push_queue_items "${VC2_QUEUE}" 3)"
echo "vc-3 queue length: $(push_queue_items "${VC3_QUEUE}" 9)"

wait_for_deployment_replicas 1 2
wait_for_scaledjob_jobs 2
wait_for_deployment_replicas 3 3

echo
echo "Remote scaling result"
show_remote_scaledobject 1
show_remote_scaledjob 2
show_remote_scaledobject 3

hold_seconds="${DEMO_HOLD_SECONDS:-20}"
echo
echo "Holding the scaled state for ${hold_seconds}s before demonstrating scale-to-zero"
sleep "${hold_seconds}"

redis_cli DEL "${VC1_QUEUE}" "${VC3_QUEUE}" >/dev/null
wait_for_deployment_replicas 1 0
wait_for_deployment_replicas 3 0

echo
echo "Scale-to-zero complete; ScaledJob history remains visible in vc-2"
show_remote_scaledobject 1
show_remote_scaledjob 2
show_remote_scaledobject 3
