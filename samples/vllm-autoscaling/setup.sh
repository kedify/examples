#!/bin/bash
#ensure your cluster supports GPU workloads before running this script
set -e


#deploy vllm
helm repo add vllm https://vllm-project.github.io/production-stack
helm upgrade -i vllm vllm/vllm-stack -f vllm-prod-stack-values.yaml

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add kedify https://kedify.github.io/charts
helm repo update open-telemetry kedify


# deploy KEDA
KEDA_VERSION=$(curl -s https://api.github.com/repos/kedify/charts/releases | jq -r '[.[].tag_name | select(. | startswith("keda/")) | sub("^keda/"; "")] | first')
KEDA_VERSION=${KEDA_VERSION:-v2.17.1-0}
helm upgrade -i keda kedify/keda --namespace keda --create-namespace --version ${KEDA_VERSION}

# install KEDA OTel Scaler & OTel Operator
helm upgrade -i keda-otel-scaler --namespace keda oci://ghcr.io/kedify/charts/otel-add-on --version=v0.1.2 -f ./otel-scaler-values.yaml

# create ScaledObject
kubectl delete -f ./vllm-so.yaml 2> /dev/null || true
kubectl apply -f ./vllm-so.yaml
