#!/bin/bash
#ensure your cluster supports GPU workloads before running this script
set -e


#deploy llm-d PD disaggregation
helm repo add llm-d-modelservice https://llm-d-incubation.github.io/llm-d-modelservice/
helm upgrade -i pd llm-d-modelservice/llm-d-modelservice -f values-pd.yaml 

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add kedify https://kedify.github.io/charts
helm repo update open-telemetry kedify


# deploy KEDA
KEDA_VERSION=$(curl -s https://api.github.com/repos/kedify/charts/releases | jq -r '[.[].tag_name | select(. | startswith("keda/")) | sub("^keda/"; "")] | first')
KEDA_VERSION=${KEDA_VERSION:-v2.17.1-0}
helm upgrade -i keda kedify/keda --namespace keda --create-namespace --version ${KEDA_VERSION}

# install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

# install KEDA OTel Scaler & OTel Operator
helm upgrade -i keda-otel-scaler --namespace keda oci://ghcr.io/kedify/charts/otel-add-on --version=v0.1.2 -f ./otel-scaler-values.yaml

# roll the deployments so that mutating webhooks injects the sidecars
kubectl rollout restart deploy/pd-llm-d-modelservice-prefill
kubectl rollout restart deploy/pd-llm-d-modelservice-decode

# create ScaledObject
kubectl delete -f ./llmd-pd-disaggregation-so.yaml 2> /dev/null || true
kubectl apply -f ./llmd-pd-disaggregation-so.yaml
