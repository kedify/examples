#!/bin/bash
set -euo pipefail

# This sample consumes the community-compatible metrics of an existing controller.
if ! kubectl -n ingress-nginx get service ingress-nginx-controller-metrics >/dev/null; then
   echo 'An existing, vendor-supported controller with patched NGINX and compatible metrics is required. See README.md.' >&2
   exit 1
fi

helm upgrade --install my-app-be \
   --namespace app \
   --create-namespace \
   oci://ghcr.io/apollographql/helm-charts/router \
   -f ./apollo-values.yaml

# kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller-metrics 10254
#open http://localhost:10254/metrics

# nginx_ingress_controller_connect_duration_seconds_count{canary="",controller_class="k8s.io/ingress-nginx",controller_namespace="ingress-nginx",controller_pod="ingress-nginx-controller-d85848749-8z66x",host="my-app-fe.local",ingress="my-app-fe",method="GET",namespace="app",path="/",service="my-app-fe",status="200"} 1

# kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 8080:80
# curl --resolve my-app-fe.local:8080:127.0.0.1 http://my-app-fe.local:8080

helm upgrade --install keda-otel-scaler \
   --namespace keda \
   --create-namespace \
   oci://ghcr.io/kedify/charts/otel-add-on \
   --version=v0.1.3 \
   -f ./otel-scaler-values.yaml

kubectl apply -f fe.yaml -f be-so.yaml -f fe-so.yaml

echo -e "continue w/:\nhey -c 100 -z 60s -t 90 -host my-app-fe.local http://localhost:8080"
#hey -c 100 -z 60s -t 90 -host my-app-fe.local http://localhost:8080
