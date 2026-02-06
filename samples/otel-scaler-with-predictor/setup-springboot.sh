#!/bin/bash
[ -z "${KEDIFY_ORG_ID}" ] && echo "Set KEDIFY_ORG_ID env variable to your org id - https://docs.kedify.io/installation/helm#getting-organization-id" && exit 1
[ -z "${KEDIFY_API_KEY}" ] && echo "Set KEDIFY_API_KEY env variable to your api key - https://docs.kedify.io/installation/helm#getting-api-key"  && exit 1

DIR="${DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

command -v figlet &> /dev/null && {
  __wid=$(/usr/bin/tput cols) && _wid=$(( __wid < 155 ? __wid : 155 ))
  figlet -w${_wid} OTel Operator + metric router + predictor
}
echo "Architecture:"
cat ${DIR}/springboot-architecture.ascii
echo -e "\n\nPredictor:"
cat ${DIR}/springboot-architecture-predictor.ascii
set -e

# setup helm repos
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add kedify https://kedify.github.io/charts
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update open-telemetry kedify prometheus grafana

# setup cluster
k3d cluster delete predictor-with-otel-scaler &> /dev/null
k3d cluster create predictor-with-otel-scaler -p "8080:31197@server:0" -p "8081:31196@server:0" -p "8082:31195@server:0"

# deploy stuff
kubectl create ns app
kubectl create ns observability
kubectl create ns keda

# Deploy Kedify with KEDA, OTel Scaler & Predictor
KEDIFY_AGENT_VERSION=$(curl -s https://api.github.com/repos/kedify/charts/releases | jq -r '[.[].tag_name | select(. | startswith("kedify-agent/")) | sub("^kedify-agent/"; "")] | first')
KEDIFY_AGENT_VERSION=${KEDIFY_AGENT_VERSION:-v0.4.13}
helm upgrade -i kedify-agent kedify/kedify-agent --namespace keda --create-namespace --version ${KEDIFY_AGENT_VERSION} -f ${DIR}/kedify-agent-values.yaml \
  --set agent.orgId=${KEDIFY_ORG_ID} \
  --set agent.apiKey=${KEDIFY_API_KEY} \
  --set clusterName=predictor-demo-$(xxd -l2 -ps /dev/urandom)

# prometheus
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
  kedify-otel-scaler \
  kedify-predictor ; do
    kubectl rollout status -n keda --timeout=600s deploy/${d}
  done
kubectl rollout status -n observability --timeout=600s \
  deploy/router-collector \
  deploy/grafana
kubectl create cm dashboard -nobservability --from-file=${DIR}/grafana-dashboard.json
kubectl label -nobservability cm dashboard --overwrite grafana_dashboard=true

# prometheus & grafana helm chart do not allow setting fixed node port
kubectl patch service prometheus-server \
  -n observability --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":31196}]'
kubectl patch service grafana \
  -n observability --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":31195}]'

# spring boot workloads (client and server apps)
# repo: https://github.com/jkremser/opentelemetry-java-examples/tree/main/spring
kubectl create deploy -napp spring-server --image=ghcr.io/kedify/springboot:tracing --port=8080
kubectl set env -napp deploy/spring-server \
      OTEL_TRACES_EXPORTER="none" \
      SERVER="" \
      SERVICE_NAME=server

kubectl create deploy -napp spring-client --image=ghcr.io/kedify/springboot:tracing
kubectl expose deploy/spring-server -napp --name=spring-server --type=NodePort --port=8080 --target-port=8080
kubectl patch svc/spring-server -napp --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":31197}]'
kubectl set env -napp deploy/spring-client \
     SERVER="http://spring-server:8080" \
     SLEEP_MS="1000" \
     OTEL_TRACES_EXPORTER="none" \
     DEADLINE=100 \
     SERVICE_NAME=client

# scraping (either make sure the pods are annotated or use OTel operator with target allocator)
kubectl patch deploy/spring-server  -napp --type=merge -p '{"spec":{"template": {"metadata":{"annotations": {
  "kedify.io/scrape": "true",
  "kedify.io/path": "/actuator/prometheus",
  "kedify.io/port": "8080"
}}}}}'
kubectl rollout status -n app --timeout=600s \
  deploy/spring-server \
  deploy/spring-client

# k port-forward spring-server-7488477f67-9tk9x 8080
# curl http://localhost:8080/actuator/prometheus
# good metric for scaling -> http_server_requests_seconds_count{error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/ping"} 156

# Metric Predictor
kubectl apply -f ${DIR}/metric-predictor.yaml

# ScaledObject using that metric
kubectl apply -f ${DIR}/so-springboot.yaml

cat <<USAGE
🚀
Continue with:
# spring boot app
curl http://localhost:8080/ping

# prometheus
open http://localhost:8081

# grafana dashboard
open http://localhost:8082/dashboards

# check metric predictors
k get mp -owide -A

# check collectors
k get otelcol -A

# create traffic
(hey -z 30s http://localhost:8080/ping &> /dev/null)&

# check how it scales out
k get hpa -napp keda-hpa-spring-server && k get so -napp spring-server

🚀
USAGE

# k3d cluster delete predictor-with-otel-scaler
