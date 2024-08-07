#!/usr/bin/env bash

set -xeuo pipefail

export KUBECONFIG=/root/.kube/config
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --for=condition=Available --namespace metallb-system deployment/controller --timeout=5m
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: killercoda
  namespace: metallb-system
spec:
  addresses:
  - 172.30.255.200-172.30.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: killercoda
  namespace: metallb-system
EOF

helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace traefik --create-namespace \
    --set providers.kubernetesIngress.allowEmptyServices=true \
    --set providers.kubernetesIngress.publishedService.enabled=true

echo "all done"
