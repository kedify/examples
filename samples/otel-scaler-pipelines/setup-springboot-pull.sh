#!/bin/bash
DIR="${DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

command -v figlet &> /dev/null && {
  __wid=$(/usr/bin/tput cols) && _wid=$(( __wid < 155 ? __wid : 155 ))
  figlet -w${_wid} OTel Operator + metric router
}
echo "Architecture (all communication goes via TLS):"
cat ${DIR}/springboot-pull-architecture.ascii
set -e

# setup helm repos
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add kedify https://kedify.github.io/charts
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update open-telemetry kedify prometheus grafana jetstack

# setup cluster
k3d cluster delete pipelines-tls &> /dev/null
k3d cluster create pipelines-tls -p "8080:31197@server:0" -p "8081:31196@server:0" -p "8082:31195@server:0"

# deploy stuff
kubectl create ns app
kubectl create ns observability
kubectl create ns keda
# cert-manager & trust-manager
helm upgrade -i --create-namespace -n cert-manager cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.18.2 --set crds.enabled=true
# https://github.com/cert-manager/trust-manager/blob/main/deploy/charts/trust-manager/values.yaml
helm upgrade -i --create-namespace -n cert-manager trust-manager jetstack/trust-manager \
 --set crds.enabled=true \
 --set secretTargets.enabled=true \
 --set secretTargets.authorizedSecretsAll=true \
 --wait --timeout=10m

# certs
kubectl apply -f ${DIR}/certs.yaml

# KEDA
KEDA_VERSION=$(curl -s https://api.github.com/repos/kedify/charts/releases | jq -r '[.[].tag_name | select(. | startswith("keda/")) | sub("^keda/"; "")] | first')
KEDA_VERSION=${KEDA_VERSION:-v2.17.1-0}
helm upgrade -i keda kedify/keda --namespace keda --create-namespace --version ${KEDA_VERSION} \
  --set certificates.certManager.enabled=true \
  --set certificates.certManager.issuer.generate=true \
  --set certificates.certManager.generateCA=true

# prometheus
helm upgrade -i --create-namespace -n observability prometheus prometheus-community/prometheus -f ${DIR}/prometheus-values.yaml

# grafana
helm upgrade -i --create-namespace -n observability grafana grafana/grafana -f ${DIR}/grafana-values.yaml

# KEDA Scaler & OTel collectors
helm upgrade -i keda-otel-scaler -nkeda oci://ghcr.io/kedify/charts/otel-add-on --version=v0.1.1 -f ${DIR}/springboot-pull-values.yaml


[ "x${SETUP_ONLY}" = "xtrue" ] && exit 0
# wait for components
for d in \
  keda-operator \
  keda-operator-metrics-apiserver \
  otel-operator \
  keda-otel-scaler ; do
    kubectl rollout status -n keda --timeout=600s deploy/${d}
  done
kubectl rollout status -n observability --timeout=600s \
  deploy/router-collector \
  deploy/grafana
kubectl create cm dashboard -nobservability --from-file=${DIR}/pull-grafana-dashboard.json
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

# pull / scraping (either make sure the pods are annotated or use OTel operator with target allocator)
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


# ScaledObject using that metric
kubectl wait -nkeda --for condition=ready --timeout=300s cert/keda-operator-tls-certificates
certSecret="-nkeda secret/keda-otel-scaler-cert-secret"
export _caCertPem=$(kubectl get $(echo $certSecret) -o'go-template={{index .data "ca.crt"}}' | base64 -d | awk '{ print "          " $0 }')
export _tlsClientKey=$(kubectl get $(echo $certSecret) -o'go-template={{index .data "tls.key"}}' | base64 -d | awk '{ print "          " $0 }')
export _tlsClientCert=$(kubectl get $(echo $certSecret) -o'go-template={{index .data "tls.crt"}}' | base64 -d | awk '{ print "          " $0 }')
kubectl apply -f <(cat ${DIR}/so-springboot-pull.yaml | envsubst)

cat <<USAGE
🚀
Continue with:
# spring boot app
curl http://localhost:8080/ping

# prometheus
open http://localhost:8081

# grafana dashboard
open http://localhost:8082/dashboards

# check collectors
k get otelcol -A

# check certs
k get cert -A -owide

# create traffic
(hey -z 30s http://localhost:8080/ping &> /dev/null)&

# check how it scales out
k get hpa -A && k get so -A

# verify SSL works
kubectl debug -it -n observability $(kubectl get po -nobservability -lapp.kubernetes.io/name=router-collector --no-headers -ocustom-columns=":metadata.name") --image=dockersec/tcpdump --target otc-container -- tcpdump -i any 'port 4317 and (tcp[tcpflags] & (tcp-syn|tcp-ack) == tcp-syn)'
# and you should be able to observe beginnings of SSL handshakes (kill springboot pod to force one)

# force cert rotations
cmctl renew -A --all

🚀
USAGE

# k3d cluster delete pipelines-tls
