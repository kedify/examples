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
  kubectl --kubeconfig "${REDIS_KUBECONFIG}" \
    --namespace redis \
    exec deployment/redis -- \
    env "REDISCLI_AUTH=$(redis_password)" redis-cli --no-auth-warning "$@"
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
}

set_remote_cpu_load() {
  local index="$1"
  local enabled="$2"
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    set env deployment/worker "CPU_LOAD=${enabled}"
  vcluster_kubectl "${index}" --namespace "${DEMO_NAMESPACE}" \
    rollout status deployment/worker --timeout="${DEMO_WAIT_TIMEOUT_SECONDS:-300}s"
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
    if [[ "${desired:-0}" == "${expected}" ]] && { [[ "${expected}" == "0" ]] || [[ "${ready:-0}" == "${expected}" ]]; }; then
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
