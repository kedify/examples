#!/usr/bin/env bash

set -xeuo pipefail

export KUBECONFIG=/root/.kube/config
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

export CAROOT=/root/.local/share/mkcert
wget -O /bin/mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-amd64
chmod +x /bin/mkcert
mkcert -install

wget -O /tmp/grpcurl.tar.gz https://github.com/fullstorydev/grpcurl/releases/download/v1.9.1/grpcurl_1.9.1_linux_x86_64.tar.gz
tar -zxvf /tmp/grpcurl.tar.gz -C /tmp
mv /tmp/grpcurl /bin/grpcurl
chmod +x /bin/grpcurl

wget -O /tmp/ghz.tar.gz https://github.com/bojand/ghz/releases/download/v0.120.0/ghz-linux-x86_64.tar.gz
tar -xzvf /tmp/ghz.tar.gz -C /tmp
mv /tmp/ghz /bin/ghz
chmod +x /bin/ghz

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
