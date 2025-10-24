#!/usr/bin/env bash

set -xeuo pipefail

name=${name:-member}

export KUBECONFIG=~/.kube/${name}
k3d cluster delete ${name} || true
k3d cluster create ${name} --api-port 6550 --k3s-arg "--tls-san=host.k3d.internal@server:*"

# setup member cluster resources - SA, RBAC, token
kubectl --context=k3d-${name} create namespace keda
kubectl --context=k3d-${name} create sa kedify-agent -n keda
kubectl --context=k3d-${name} apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kedify-agent-token
  namespace: keda
  annotations:
    kubernetes.io/service-account.name: kedify-agent
type: kubernetes.io/service-account-token
EOF
kubectl --context=k3d-${name} create clusterrole kedify-agent --verb=get,list,watch --resource=deployments
kubectl --context=k3d-${name} create clusterrolebinding kedify-agent --clusterrole=kedify-agent --serviceaccount=keda:kedify-agent
kubectl --context=k3d-${name} patch sa kedify-agent -n keda -p '{"secrets":[{"name":"kedify-agent-token"}]}'

# create kubeconfig for the member cluster to be used by kedify-agent in KEDA cluster
ca=$(kubectl --context=k3d-${name} get secret kedify-agent-token -n keda -o jsonpath="{.data['ca\.crt']}")
token=$(kubectl --context=k3d-${name} get secret kedify-agent-token -n keda -o jsonpath="{.data['token']}" | base64 --decode)
server=https://host.k3d.internal:6550
cat <<EOF > /tmp/kedify-agent-${name}-kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca}
    server: ${server}
  name: ${name}-cluster
contexts:
- context:
    cluster: ${name}-cluster
    user: kedify-agent
  name: kedify-agent@${name}-cluster
current-context: kedify-agent@${name}-cluster
users:
- name: kedify-agent
  user:
    token: ${token}
EOF

# add the kubeconfig to the secret that already exists in the keda cluster
export KUBECONFIG=~/.kube/config
kubectl -nkeda create secret generic kedify-agent-multicluster-kubeconfigs --from-file=${name}-cluster.kubeconfig=/tmp/kedify-agent-${name}-kubeconfig --dry-run=client -o yaml | kubectl -nkeda apply -f -
