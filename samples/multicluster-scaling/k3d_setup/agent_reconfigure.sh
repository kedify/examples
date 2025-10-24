#!/usr/bin/env bash

set -xeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# create a secret that will allow dynamic loading of kubeconfigs in kedify-agent
kubectl create secret -nkeda generic kedify-agent-multicluster-kubeconfigs

# mount the secret as dir /etc/mc/kubeconfigs in kedify-agent deployment
kubectl -nkeda patch deployment kedify-agent --type='json' -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"kubeconfigs","secret":{"secretName":"kedify-agent-multicluster-kubeconfigs"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"kubeconfigs","mountPath":"/etc/mc/kubeconfigs","readOnly":true}}]'

# apply CRDs and RBAC
kubectl apply -f "$DIR/../config/crd/bases/keda.kedify.io_distributedscaledobjects.yaml"
kubectl apply -f "$DIR/../config/rbac/role.yaml"
