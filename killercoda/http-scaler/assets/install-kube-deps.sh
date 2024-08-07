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

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

echo "all done"
