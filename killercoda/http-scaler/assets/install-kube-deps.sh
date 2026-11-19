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

helm upgrade --install traefik traefik \
  --repo https://traefik.github.io/charts \
  --version 42.4.0 \
  --namespace traefik --create-namespace \
  --skip-crds \
  --set providers.kubernetesCRD.enabled=false \
  --set ingressClass.enabled=false \
  --set providers.kubernetesIngress.enabled=false \
  --set providers.kubernetesIngressNGINX.enabled=true \
  --set providers.kubernetesIngressNGINX.publishService.enabled=true

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF

echo "all done"
