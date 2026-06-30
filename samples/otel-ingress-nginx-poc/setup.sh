#!/bin/bash

k apply -f https://raw.githubusercontent.com/prometheus-community/helm-charts/refs/heads/main/charts/kube-prometheus-stack/charts/crds/crds/crd-servicemonitors.yaml
helm upgrade -i msol-app-bff-main \
   --namespace other-app \
   --create-namespace \
   oci://ghcr.io/apollographql/helm-charts/router \
   -f apollo-values.yaml

helm upgrade -i ingress-nginx ingress-nginx --reuse-values \
   https://kubernetes.github.io/ingress-nginx \
   --namespace ingress-nginx \
   --set controller.metrics.enabled=true

#k port-forward svc/ingress-nginx-controller-metrics 10254 -ningress-nginx
#open http://localhost:10254/metrics

# nginx_ingress_controller_connect_duration_seconds_count{canary="",controller_class="k8s.io/ingress-nginx",controller_namespace="ingress-nginx",controller_pod="ingress-nginx-controller-d85848749-8z66x",host="msol-app-fe-main.local",ingress="msol-app-fe-main",method="GET",namespace="app",path="/",service="msol-app-fe-main",status="200"} 1

# k port-forward -ningress-nginx service/ingress-nginx-controller 8080:80
# curl --resolve msol-app-fe-main.local:8080:127.0.0.1 http://msol-app-fe-main.local:8080

helm upgrade -i keda-otel-scaler -nkeda \
 oci://ghcr.io/kedify/charts/otel-add-on \
 --version=v0.1.3 \
 -f ./otel-scaler-values.yaml

k apply -f fe.yaml -f be-so.yaml -f fe-so.yaml

echo -e "continue w/:\nhey -c 100 -z 60s -t 90 -host msol-app-fe-main.local http://localhost:8080"
#hey -c 100 -z 60s -t 90 -host msol-app-fe-main.local http://localhost:8080
