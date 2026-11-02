#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.local/bin:$PATH"
export KUBECONFIG="$PWD/.local/kubeconfig"
ctx=mobility-global
flux get all -A --context "$ctx"
kubectl --context "$ctx" -n demo get deployment,scaledobject,hpa,metricpredictor
kubectl --context "$ctx" -n keda get pods,pvc
kubectl --context "$ctx" get apiservice v1beta1.external.metrics.k8s.io
