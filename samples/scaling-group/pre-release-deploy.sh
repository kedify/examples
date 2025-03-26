#!/usr/bin/env bash

set -euo pipefail

# figure out the cluster name
if kubectl get kedifyconfiguration -nkeda > /dev/null 2>&1; then
  cluster_name=$(kubectl get kedifyconfiguration -nkeda -ojson kedify | jq -r '.spec.clusterName')
else
  cluster_name="test-helm-$(head /dev/urandom | sha1sum | cut -c1-8)"
fi

# KEDA helm chart values
keda_values=$(cat <<EOF
env:
  - name: KEDIFY_SCALINGGROUPS_ENABLED
    value: "true"
EOF
)

# KEDA add-on helm chart values
addon_values=$(cat <<EOF
scaler:
  pullPolicy: IfNotPresent
interceptor:
  pullPolicy: IfNotPresent
  additionalEnvVars:
    - name: KEDIFY_EXPERIMENTAL_H2C_ENABLED
      value: "true"
EOF
)

# Kedify agent helm chart values
# for KEDIFY_ORG_ID and KEDIFY_API_KEY consult https://kedify.io/documentation/getting-started/helm
agent_values=$(cat <<EOF
clusterName: $cluster_name
agent:
  kedifyServer: kedify-proxy.api.dev.kedify.io:443
  orgId: "$KEDIFY_ORG_ID"
  apiKey: "$KEDIFY_API_KEY"

  kedifyProxy:
    globalValues:
      autoscaling:
        enabled: true
      podDisruptionBudget:
        enabled: true
EOF
)

# install all three charts
helm upgrade --install keda kedifykeda/keda --namespace keda --create-namespace --version v2.17.0-rc0 --values <(echo "$keda_values")
helm upgrade --install keda-add-ons-http kedifykeda/keda-add-ons-http --namespace keda --version v0.10.0-1 --values <(echo "$addon_values")
helm upgrade --install kedify-agent kedifykeda/kedify-agent --namespace keda --version v0.2.1 --values <(echo "$agent_values")
