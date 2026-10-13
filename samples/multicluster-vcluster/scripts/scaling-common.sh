#!/usr/bin/env bash

# Shared helpers for the remote ScaledObject and ScaledJob presentation.

export DEMO_NAMESPACE="${DEMO_NAMESPACE:-demo-scaling}"
export VC2_QUEUE="${VC2_QUEUE:-demo-vc2-scaledjob}"
export VC3_QUEUE="${VC3_QUEUE:-demo-vc3-scaledobject}"

require_scaling_state() {
  require_command kubectl vcluster sed timeout
  require_file "${MAIN_KUBECONFIG}"
  require_file "${REDIS_KUBECONFIG}"
  require_file "${REPO_ROOT}/state/redis-ip"
  require_file "${REPO_ROOT}/state/redis-password"
}

redis_address() {
  printf '%s:6379' "$(<"${REPO_ROOT}/state/redis-ip")"
}

redis_host() {
  printf '%s' "$(<"${REPO_ROOT}/state/redis-ip")"
}

redis_password() {
  printf '%s' "$(<"${REPO_ROOT}/state/redis-password")"
}

redis_cli() {
  # Pass the password on stdin so process arguments and presentation commands
  # never contain it. Disable tracing before reading credential state.
  set +x
  printf '%s\n' "$(redis_password)" | kubectl --kubeconfig "${REDIS_KUBECONFIG}" \
    --namespace redis \
    exec -i deployment/redis -- \
    sh -c 'IFS= read -r REDISCLI_AUTH; export REDISCLI_AUTH; exec redis-cli --no-auth-warning "$@"' sh "$@"
}

clear_demo_queues() {
  redis_cli DEL "${VC2_QUEUE}" "${VC3_QUEUE}" >/dev/null
}

push_queue_items() {
  local queue="$1"
  local count="$2"
  local args=(LPUSH "${queue}")
  local index
  for ((index = 1; index <= count; index++)); do
    args+=("demo-item-${index}")
  done
  redis_cli "${args[@]}"
}

verify_main_to_redis_connectivity() {
  local pod="redis-connectivity-check"
  kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
    --namespace "${NAMESPACE}" \
    delete pod "${pod}" --ignore-not-found --wait=true >/dev/null
  timeout 120s kubectl --kubeconfig "${MAIN_KUBECONFIG}" \
    --namespace "${NAMESPACE}" \
    run "${pod}" \
    --image=redis:7.4-alpine \
    --restart=Never \
    --rm \
    --attach \
    --env="REDISCLI_AUTH=$(redis_password)" \
    --command -- redis-cli --no-auth-warning -h "$(redis_host)" -p 6379 PING
}

wait_for_remote_metrics_api() {
  local index="$1"
  local deadline=$((SECONDS + ${DEMO_WAIT_TIMEOUT_SECONDS:-300}))
  while ((SECONDS < deadline)); do
    if vcluster_kubectl "${index}" get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; then
      echo "vc-${index} metrics.k8s.io API is available"
      return 0
    fi
    sleep 3
  done
  echo "timed out waiting for metrics.k8s.io in vc-${index}" >&2
  echo "run 'make vclusters' to apply the metrics-server integration" >&2
  return 1
}

apply_remote_auth_secret() {
  local index="$1"
  local manifest
  manifest="$(mktemp /tmp/kedify-demo-redis-secret.XXXXXX.yaml)"
  kubectl create secret generic redis-auth \
    --namespace "${DEMO_NAMESPACE}" \
    --from-literal="address=$(redis_address)" \
    --from-literal="host=$(redis_host)" \
    --from-literal="password=$(redis_password)" \
    --dry-run=client \
    --output yaml >"${manifest}"
  if ! vcluster_kubectl "${index}" apply -f "${manifest}"; then
    rm -f "${manifest}"
    return 1
  fi
  rm -f "${manifest}"
}

apply_remote_template() {
  local index="$1"
  local template="$2"
  local queue="$3"
  local manifest
  manifest="$(mktemp /tmp/kedify-demo-scaling.XXXXXX.yaml)"
  sed \
    -e "s/__NAMESPACE__/${DEMO_NAMESPACE}/g" \
    -e "s/__QUEUE__/${queue}/g" \
    "${template}" >"${manifest}"
  if ! vcluster_kubectl "${index}" apply -f "${manifest}"; then
    rm -f "${manifest}"
    return 1
  fi
  rm -f "${manifest}"
}

deploy_remote_scaledobject() {
  local index="$1"
  local queue="$2"
  vcluster_kubectl "${index}" create namespace "${DEMO_NAMESPACE}" --dry-run=client --output yaml | \
    vcluster_kubectl "${index}" apply -f -
  apply_remote_auth_secret "${index}"
  apply_remote_template "${index}" "${REPO_ROOT}/manifests/scaling/scaledobject.yaml" "${queue}"
}

deploy_remote_cpu_scaledobject() {
  local index="$1"
  vcluster_kubectl "${index}" create namespace "${DEMO_NAMESPACE}" --dry-run=client --output yaml | \
    vcluster_kubectl "${index}" apply -f -
  apply_remote_template "${index}" "${REPO_ROOT}/manifests/scaling/cpu-scaledobject.yaml" unused
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    rollout status deployment/worker --timeout="${DEMO_WAIT_TIMEOUT_SECONDS:-300}s"
  set_remote_cpu_load "${index}" false
}

wait_for_remote_cpu_metrics() {
  local index="$1"
  require_command python3
  # One persistent connection while waiting, independent of the presentation panes.
  KUBECONFIG="${MAIN_KUBECONFIG}" vcluster connect "$(vcluster_release_name "${index}")" \
    --namespace "$(vcluster_namespace "${index}")" --background-proxy=false --silent \
    -- python3 -B "${REPO_ROOT}/scripts/demo-observer.py" cpu-ready
}

set_remote_cpu_load() {
  local index="$1"
  local enabled="$2"
  local control pods pod phase deleting count=0
  [[ "${enabled}" == true || "${enabled}" == false ]] || { echo 'Expected CPU load true or false' >&2; return 1; }
  control="$(vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get deployment worker \
    --output 'jsonpath={.metadata.annotations.demo\.kedify\.io/cpu-control}')"
  [[ "${control}" == file-v1 ]] || { echo 'CPU fixture needs updating: run make prepare-scaling-demo before the presentation' >&2; return 1; }
  if [[ "${enabled}" == true ]]; then
    wait_for_remote_cpu_metrics "${index}"
  fi
  pods="$(vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get pods --selector app=worker \
    --output 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.metadata.deletionTimestamp}{"\n"}{end}')"
  # Only Deployment metadata changes. A partial/failed toggle stays unknown;
  # it must never be presented as a successful on/off state.
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    annotate deployment/worker demo.kedify.io/cpu-load=unknown --overwrite >/dev/null
  while read -r pod phase deleting; do
    [[ -n "${pod}" && "${phase}" == Running && -z "${deleting}" ]] || continue
    if [[ "${enabled}" == true ]]; then
      # Keep the warm load source when the ReplicaSet later returns to one Pod.
      # New scale-out Pods start idle and retain the default deletion cost.
      vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" annotate "pod/${pod}" \
        controller.kubernetes.io/pod-deletion-cost=100 --overwrite >/dev/null
    fi
    # The quoted program runs in the worker container; $1 is its load argument.
    # shellcheck disable=SC2016
    vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" exec "${pod}" -- sh -c '
      test -f /tmp/kedify-demo-cpu-control || exit 1
      if [ "$1" = true ]; then touch /tmp/kedify-demo-cpu-load; else rm -f /tmp/kedify-demo-cpu-load; fi
    ' sh "${enabled}" || return 1
    count=$((count + 1))
    [[ "${enabled}" == false ]] || break
  done <<<"${pods}"
  ((count > 0)) || { echo 'No running worker Pods found; CPU load state is unknown' >&2; return 1; }
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    annotate deployment/worker "demo.kedify.io/cpu-load=${enabled}" --overwrite >/dev/null
  echo "vc-${index} CPU load ${enabled} in ${count} existing Pod(s); no Deployment rollout"
}

deploy_remote_scaledjob() {
  local index="$1"
  local queue="$2"
  vcluster_kubectl "${index}" create namespace "${DEMO_NAMESPACE}" --dry-run=client --output yaml | \
    vcluster_kubectl "${index}" apply -f -
  apply_remote_auth_secret "${index}"
  apply_remote_template "${index}" "${REPO_ROOT}/manifests/scaling/scaledjob.yaml" "${queue}"
}

wait_for_remote_resource() {
  local index="$1"
  local resource="$2"
  local deadline=$((SECONDS + ${DEMO_WAIT_TIMEOUT_SECONDS:-300}))
  while ((SECONDS < deadline)); do
    if vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get "${resource}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for ${resource} in vc-${index}" >&2
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get scaledobjects,scaledjobs,kedifypodautoscalers,deployments,jobs,pods >&2 || true
  return 1
}

wait_for_deployment_replicas() {
  local index="$1"
  local expected="$2"
  local current=""
  local desired=""
  local ready=""
  local deadline=$((SECONDS + ${DEMO_WAIT_TIMEOUT_SECONDS:-300}))
  while ((SECONDS < deadline)); do
    current="$(vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get deployment worker --output 'jsonpath={.spec.replicas}:{.status.readyReplicas}' 2>/dev/null || true)"
    desired="${current%%:*}"
    ready="${current#*:}"
    # A failed/empty API response is unknown, including while waiting for zero.
    # Require an observed spec.replicas and wait for old ready Pods to disappear.
    if [[ "${current}" == *:* && "${desired}" == "${expected}" && "${ready:-0}" == "${expected}" ]]; then
      echo "vc-${index} worker reached ${expected} desired and ready replicas"
      return 0
    fi
    sleep 3
  done
  echo "timed out waiting for vc-${index} worker replicas=${expected}; observed desired=${desired:-unknown}, ready=${ready:-0}" >&2
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    get scaledobjects,kedifypodautoscalers,deployments,pods >&2 || true
  return 1
}

wait_for_scaledjob_jobs() {
  local index="$1"
  local deadline=$((SECONDS + ${DEMO_WAIT_TIMEOUT_SECONDS:-300}))
  local count=0
  while ((SECONDS < deadline)); do
    count="$(vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get jobs \
      --selector scaledjob.keda.sh/name=worker \
      --output name 2>/dev/null | wc -l)"
    if ((count > 0)); then
      echo "vc-${index} ScaledJob created ${count} Job(s)"
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for vc-${index} ScaledJob to create Jobs" >&2
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" get scaledjob,jobs,pods >&2 || true
  return 1
}

show_remote_scaledobject() {
  local index="$1"
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    get scaledobject,triggerauthentication,kedifypodautoscaler,deployments,pods
}

show_remote_scaledjob() {
  local index="$1"
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    get scaledjob,triggerauthentication,jobs,pods
}
