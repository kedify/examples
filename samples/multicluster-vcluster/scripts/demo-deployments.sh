#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/presentation-common.sh"

demo_heading "${1:?Pass the cluster label} / Deployments in every namespace"
demo_command 'kubectl get deployments --all-namespaces'
kubectl get deployments --all-namespaces
