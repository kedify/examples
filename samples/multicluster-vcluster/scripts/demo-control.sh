#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/vcluster-common.sh"
source "$(dirname "$0")/scaling-common.sh"
source "$(dirname "$0")/presentation-common.sh"

action="${1:-help}"
case "${action}" in
  help)
    demo_heading 'One central control plane. Independent vCluster workloads.'
    printf '%-26s %s\n' \
      'make demo-baseline' 'Reset only demo fixtures and vc-3; prepare two idle tenants' \
      'make demo-preflight' 'Read-only checks of the two-tenant baseline' \
      'make demo-iterm2' 'Native iTerm2 observer and manual-control tabs (macOS)' \
      'make demo-iterm2-extras' 'Add Deployment watches and interactive resource tabs' \
      'make demo-deployments PANE=host' 'Watch all Deployments (PANE=1, 2, or 3 for tenants)' \
      'make demo-resources PANE=host' 'Interactive kubectl shell (PANE=1, 2, or 3 for tenants)' \
      'make demo-pane PANE=host' 'Host fleet view (native iTerm2 pane)' \
      'make demo-pane PANE=1' 'vc-1 CPU view (use PANE=2 or 3 for the other tenants)' \
      'make demo-tmux' 'Optional tmux layout with the same four observer panes' \
      'make demo-cpu-on' 'vc-1: 1 -> 3 replicas from bounded CPU load' \
      'make demo-cpu-off' 'vc-1: return to one idle replica' \
      'make demo-jobs' 'vc-2: enqueue three items; observe native Jobs' \
      'make demo-jobs-clear' 'vc-2: clear queued demand; running Jobs may finish' \
      'make demo-jobs-reset' 'vc-2: clear demand and Job history; prepare a clean rerun' \
      'make third-vcluster' 'Create vc-3 and watch discovery / registration' \
      'make demo-workload' 'Create an ordinary ScaledObject inside vc-3' \
      'make demo-queue-on' 'vc-3: nine items -> three replicas' \
      'make demo-queue-off' 'vc-3: clear the simulated backlog -> zero replicas'
    printf '%-26s %s\n' \
      'make demo-queue-clear' 'Clear vc-3 demand even if its worker or tenant is absent' \
      'make demo-tenant-reset' 'Clear vc-3 demand; remove tenant and generated registration'
    exit 0
    ;;
  cpu-on|cpu-off|jobs|jobs-clear|jobs-reset|workload|queue-on|queue-off|queue-clear|tenant-reset|baseline|preflight) ;;
  *) printf 'Unknown demo action: %s\n' "${action}" >&2; exit 2 ;;
esac

require_scaling_state
case "${action}" in
  baseline)
    demo_heading 'Restore the two-vCluster presentation baseline'
    demo_note 'Removes demo-scaling fixtures and vc-3. Azure infrastructure and central controllers stay deployed.'
    "${REPO_ROOT}/scripts/reset-scaling-demo.sh"
    "${REPO_ROOT}/scripts/reset-third-vcluster.sh"
    "${REPO_ROOT}/scripts/prepare-scaling-demo.sh"
    "${REPO_ROOT}/scripts/demo-control.sh" preflight
    ;;
  preflight)
    require_command python3
    demo_heading 'Read-only presentation checks'
    "${REPO_ROOT}/scripts/verify.sh"
    [[ "$(redis_cli PING)" == PONG ]]
    for queue in "${VC2_QUEUE}" "${VC3_QUEUE}"; do
      [[ "$(redis_cli LLEN "${queue}")" == 0 ]] || { printf 'Queue is not empty: %s\n' "${queue}" >&2; exit 1; }
    done
    wait_for_remote_cpu_metrics 1
    wait_for_deployment_replicas 1 1
    cpu_load="$(vcluster_kubectl 1 --namespace "${DEMO_NAMESPACE}" get deployment worker --output 'jsonpath={.metadata.annotations.demo\.kedify\.io/cpu-load}')"
    [[ "${cpu_load}" == false ]] || { printf 'vc-1 CPU load is enabled\n' >&2; exit 1; }
    jobs="$(vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" get jobs --selector scaledjob.keda.sh/name=worker --output name)"
    [[ -z "${jobs}" ]] || { printf 'vc-2 still has Job history; run make demo-baseline\n' >&2; exit 1; }
    vcluster_kubectl 1 --namespace "${DEMO_NAMESPACE}" get scaledobject,kpa
    vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" get scaledjob
    demo_ok 'Two registrations, remote CPU metrics, idle worker, empty queues, and clean Job history'
    demo_note 'Registration readiness validates access. The live scaling steps verify the KEDA/KPA consumers.'
    ;;
  cpu-on|cpu-off)
    enabled=false
    expected=1
    if [[ "${action}" == cpu-on ]]; then enabled=true; expected=3; fi
    demo_heading "vc-1 / CPU: desired outcome ${expected} ready replicas"
    demo_command "set_remote_cpu_load 1 ${enabled}"
    set_remote_cpu_load 1 "${enabled}"
    wait_for_deployment_replicas 1 "${expected}"
    demo_ok "vc-1 worker: ${expected} desired and ready replicas"
    ;;
  jobs)
    wait_for_vcluster_registration 2
    [[ "$(redis_cli LLEN "${VC2_QUEUE}")" == 0 ]] || { printf 'vc-2 queue already contains demand\n' >&2; exit 1; }
    demo_heading 'vc-2 / authenticated ScaledJob'
    demo_command "push_queue_items \"\$VC2_QUEUE\" 3"
    push_queue_items "${VC2_QUEUE}" 3
    wait_for_scaledjob_jobs 2
    demo_ok 'Remote Jobs created; keep the vc-2 pane visible for consumption and completion'
    demo_note 'ScaledJobs create Jobs, not a KPA. At most three Jobs run concurrently.'
    ;;
  jobs-clear)
    demo_heading 'vc-2 / clear queued demand'
    demo_command "redis_cli DEL \"\$VC2_QUEUE\""
    redis_cli DEL "${VC2_QUEUE}" >/dev/null
    demo_ok 'vc-2 queue is empty'
    demo_note 'This does not cancel Jobs that already fetched an item. Use demo-jobs-reset for a clean rerun.'
    ;;
  jobs-reset)
    wait_for_vcluster_registration 2
    demo_heading 'vc-2 / reset Jobs demonstration'
    redis_cli DEL "${VC2_QUEUE}" >/dev/null
    # Remove the producer before deleting Job history so a pending scaler
    # evaluation cannot create more Jobs during cleanup.
    demo_command 'kubectl -n demo-scaling delete scaledjob worker; delete its Jobs; reapply the fixture'
    vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" delete scaledjob worker \
      --ignore-not-found --cascade=foreground --wait=true --timeout="${DEMO_WAIT_TIMEOUT_SECONDS:-300}s"
    vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" delete jobs \
      --selector scaledjob.keda.sh/name=worker --ignore-not-found \
      --cascade=foreground --wait=true --timeout="${DEMO_WAIT_TIMEOUT_SECONDS:-300}s"
    deploy_remote_scaledjob 2 "${VC2_QUEUE}"
    wait_for_remote_resource 2 scaledjob.keda.sh/worker
    [[ "$(redis_cli LLEN "${VC2_QUEUE}")" == 0 ]]
    jobs="$(vcluster_kubectl 2 --namespace "${DEMO_NAMESPACE}" get jobs \
      --selector scaledjob.keda.sh/name=worker --output name)"
    [[ -z "${jobs}" ]] || { printf 'Job history is not empty after reset\n' >&2; exit 1; }
    demo_ok 'vc-2 queue and Job history are empty; make demo-jobs is ready'
    ;;
  workload)
    wait_for_vcluster_registration 3
    [[ "$(redis_cli LLEN "${VC3_QUEUE}")" == 0 ]] || { printf 'Clear vc-3 demand before applying the fixture\n' >&2; exit 1; }
    demo_heading 'vc-3 / developer-owned ScaledObject'
    demo_command "deploy_remote_scaledobject 3 \"\$VC3_QUEUE\""
    deploy_remote_scaledobject 3 "${VC3_QUEUE}"
    wait_for_remote_resource 3 kedifypodautoscaler.autoscaling.kedify.io/worker-autoscaler
    wait_for_deployment_replicas 3 0
    demo_ok 'New member reconciles its ordinary ScaledObject; worker is at zero'
    ;;
  queue-on)
    vcluster_kubectl 3 --namespace "${DEMO_NAMESPACE}" get scaledobject/worker >/dev/null
    [[ "$(redis_cli LLEN "${VC3_QUEUE}")" == 0 ]] || { printf 'vc-3 queue already contains demand\n' >&2; exit 1; }
    demo_heading 'vc-3 / Redis: nine items, three items per replica'
    demo_command "push_queue_items \"\$VC3_QUEUE\" 9"
    push_queue_items "${VC3_QUEUE}" 9
    wait_for_deployment_replicas 3 3
    demo_ok 'vc-3 worker: three desired and ready replicas'
    demo_note 'The placeholder Deployment does not consume Redis; clear its simulated backlog manually.'
    ;;
  queue-off)
    demo_heading 'vc-3 / remove the simulated demand'
    demo_command "redis_cli DEL \"\$VC3_QUEUE\""
    redis_cli DEL "${VC3_QUEUE}" >/dev/null
    wait_for_deployment_replicas 3 0
    demo_ok 'vc-3 worker returned to zero replicas'
    ;;
  queue-clear)
    demo_heading 'vc-3 / clear Redis demand without waiting for a worker'
    demo_command "redis_cli DEL \"\$VC3_QUEUE\""
    redis_cli DEL "${VC3_QUEUE}" >/dev/null
    demo_ok 'vc-3 queue is empty'
    ;;
  tenant-reset)
    demo_heading 'vc-3 / remove the tenant and its generated registration'
    redis_cli DEL "${VC3_QUEUE}" >/dev/null
    "${REPO_ROOT}/scripts/reset-third-vcluster.sh"
    demo_ok 'vc-3 demand, tenant and registration removed'
    demo_note 'Repeat make third-vcluster, then make demo-workload when ready.'
    ;;
esac
