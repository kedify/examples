#!/bin/bash
[ -z "${KEDIFY_ORG_ID}" ] && echo "Set KEDIFY_ORG_ID env variable to your org id - https://docs.kedify.io/installation/helm#getting-organization-id" && exit 1
[ -z "${KEDIFY_API_KEY}" ] && echo "Set KEDIFY_API_KEY env variable to your api key - https://docs.kedify.io/installation/helm#getting-api-key"  && exit 1

DIR="${DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

command -v figlet &> /dev/null && {
  __wid=$(/usr/bin/tput cols) && _wid=$(( __wid < 155 ? __wid : 155 ))
  figlet -w${_wid} OTel Operator + OTel Scaler + PRP
}
echo "Architecture:"
cat ${DIR}/architecture.ascii
set -e

# setup cluster
k3d cluster delete otel-scaler-vertical &> /dev/null
k3d cluster create otel-scaler-vertical --no-lb --k3s-arg "--disable=traefik,servicelb@server:*" --k3s-arg "--kube-apiserver-arg=feature-gates=InPlacePodVerticalScaling=true@server:*"

# check if k3d supports InPlacePodVerticalScaling feature gate
kubectl create deploy test-in-place-resize --image=nginx
kubectl set resources deploy test-in-place-resize --requests=memory=40Mi
sleep 5 && kubectl rollout status deploy test-in-place-resize
kubectl patch po $(kubectl get po -lapp=test-in-place-resize -ojsonpath="{.items[0].metadata.name}") --type=json -p '[{"op":"replace","path":"/spec/containers/0/resources/requests/memory","value":"45Mi"}]' || {
  echo "Failed to patch the pod's resources, make sure the k8s cluster supports InPlacePodVerticalScaling feature gate, exiting..." && exit 1
}
kubectl delete deploy test-in-place-resize

# setup helm repos
helm repo add kedify https://kedify.github.io/charts
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update kedify prometheus grafana

# Deploy Kedify with KEDA, OTel Scaler and OTel operator
KEDIFY_AGENT_VERSION=$(curl -s https://api.github.com/repos/kedify/charts/releases | jq -r '[.[].tag_name | select(. | startswith("kedify-agent/")) | sub("^kedify-agent/"; "")] | first')
KEDIFY_AGENT_VERSION=${KEDIFY_AGENT_VERSION:-v0.4.13}
helm upgrade -i kedify-agent kedify/kedify-agent --namespace keda --create-namespace --version ${KEDIFY_AGENT_VERSION} -f ${DIR}/kedify-agent-values.yaml \
  --set agent.orgId=${KEDIFY_ORG_ID} \
  --set agent.apiKey=${KEDIFY_API_KEY} \
  --set clusterName=otel-scaler-vertical-$(xxd -l2 -ps /dev/urandom)

# prometheus (used only by Grafana for visualization, not used for scaling in this example)
helm upgrade -i --create-namespace -n observability prometheus prometheus-community/prometheus -f ${DIR}/prometheus-values.yaml

# grafana
helm upgrade -i --create-namespace -n observability grafana grafana/grafana -f ${DIR}/grafana-values.yaml

# # KEDA Scaler & OTel collectors (when using own OTel operator, make sure otelOperator.enabled=false)
helm upgrade -i kedify-otel-scaler -nkeda oci://ghcr.io/kedify/charts/otel-add-on --version=v0.1.3 -f ${DIR}/otel-scaler-values.yaml

[ "x${SETUP_ONLY}" = "xtrue" ] && exit 0
# wait for components
for d in \
  keda-operator \
  keda-operator-metrics-apiserver \
  otel-operator \
  kedify-otel-scaler; do
    kubectl rollout status -n keda --timeout=600s deploy/${d}
  done
kubectl rollout status -n observability --timeout=600s \
  deploy/router-collector \
  deploy/grafana
kubectl create cm dashboard -nobservability --from-file=${DIR}/grafana-dashboard.json
kubectl label -nobservability cm dashboard --overwrite grafana_dashboard=true

# sample workload (podinfo app)
helm upgrade -i --wait --timeout 600s --create-namespace podinfo -napp oci://ghcr.io/stefanprodan/charts/podinfo -f ${DIR}/podinfo-values.yaml
kubectl rollout status -n app --timeout=600s deploy/podinfo

# k port-forward svc/podinfo 9898
# curl http://localhost:9898/metrics
# good metric for scaling:
# HELP go_goroutines Number of goroutines that currently exist.
# TYPE go_goroutines gauge
# go_goroutines 12

# ScaledObject using that metric (we will use it only for vertical scaling, but you can also use it for horizontal scaling):
kubectl apply -f ${DIR}/so-podinfo.yaml

# PodResourceProfile(PRP) using that metric for vertical scaling:
kubectl apply -f ${DIR}/prp-podinfo.yaml

# port forwarding to access the app, prometheus and grafana dashboards
(kubectl port-forward -napp svc/podinfo 9898 &> /dev/null)& pi_pid=$!
(sleep 15m && kill ${pi_pid})&

(kubectl port-forward -nobservability svc/prometheus-server 8081:80 &> /dev/null)& pp_pid=$!
(sleep 15m && kill ${pp_pid})&

(kubectl port-forward -nobservability svc/grafana 8082:80 &> /dev/null)& pg_pid=$!
(sleep 15m && kill ${pg_pid})&

# print usage
cat <<USAGE
🚀
Continue with:
# podinfo app
curl http://localhost:9898

# metric that drives the vertical scaling
curl http://localhost:9898/metrics | grep go_goroutines

# prometheus
open http://localhost:8081

# grafana dashboard
open http://localhost:8082/dashboards

# check collectors
k get otelcol -A

# check PodResourceProfiles
k get prp -owide -A

# create traffic
(hey -z 60s http://localhost:9898 &> /dev/null)&

# check how it scales up/down (replicas will be always 1, but the resources will be adjusted based on the load)
k get hpa -napp keda-hpa-podinfo && k get so -napp podinfo && k get prp -napp podinfo

watch "k get hpa -napp keda-hpa-podinfo && k get so -napp podinfo && k get prp -napp podinfo"
watch "kubectl get po -napp -lapp.kubernetes.io/name=podinfo -ojsonpath=\"{.items[*].spec.containers[?(.name=='podinfo')].resources}\" | jq"

🚀
USAGE

# k3d cluster delete otel-scaler-vertical
