# Scaling a Deployment with Kedify-Envoy-HTTP Trigger

This example demonstrates how to use the `kedify-envoy-http` trigger to scale a deployment based on the request rate.

[Official Documentation](https://kedify.io/documentation/scalers/http-envoy-scaler/)

## Things to Check

### 1. Verify Interceptor Internal Envoy Metrics Map
Ensure that the internal envoy metrics map is correctly formed.

```sh
kubectl get --raw /api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/envoy-metrics-map
```

Expected Output:
```json
{"default/test": "default/http-server"}
```

### 2. Verify Envoy Connection to Interceptor Metrics Sink
Ensure that Envoy is connected to the interceptor metrics sink and is sending metrics.

```sh
kubectl get --raw /api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-metrics:2223/proxy/metrics | grep '^kedify'
```

Example Output:
```sh
kedify_envoysink_metrics_cluster_name_ignored{envoy_cluster_name="kedify_metrics_service",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 320
kedify_envoysink_metrics_flushes_processed_total{envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 17440
kedify_envoysink_metrics_sessions_current{envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 1
```

### 3. Verify Routing
Ensure that routing works correctly.

```sh
curl -I -H host:demo.keda http://$(kubectl get ingress -o json envoy | jq -r '.status.loadBalancer.ingress[].ip')
```

Expected Response:
```sh
HTTP/1.1 200 OK
Content-Length: 320
Content-Type: text/html
Date: Wed, 12 Mar 2025 07:45:12 GMT
Server: envoy
X-Envoy-Upstream-Service-Time: 0
```

### 4. Verify Metrics Queue in the Interceptor
Ensure that the metrics queue in the interceptor is operational.

```sh
kubectl get --raw /api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue
```

Example Output:
```json
{"default/http-server":{"Concurrency":0,"RPS":0.041}}
```

### 5. Check the Scaling
Use `hey` to generate traffic and verify scaling.

```sh
hey -z 5m -c 500 -q 500 -host demo.keda http://$(kubectl get ingress -o json envoy | jq -r '.status.loadBalancer.ingress[].ip')
```

Example Status Code Distribution:
```sh
[200] 331208 responses
```

Verify queue metrics:

```sh
kubectl get --raw /api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue
```

Expected Output:
```json
{"default/http-server":{"Concurrency":151,"RPS":12411.918}}
```

Check Horizontal Pod Autoscaler (HPA):

```sh
kubectl get hpa keda-hpa-http-server
```

Example Output:
```sh
NAME                   REFERENCE                TARGETS             MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-http-server   Deployment/http-server   1215200m/10 (avg)   1         10        10         17m
```

Verify updated envoy metrics:

```sh
kubectl get --raw /api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-metrics:2223/proxy/metrics | grep '^kedify'
```

Example Output:
```sh
kedify_envoysink_metrics_cluster_name_ignored{envoy_cluster_name="kedify_metrics_service",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 1324
kedify_envoysink_metrics_concurrent_set_count{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 442
kedify_envoysink_metrics_concurrent_set_current{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 83
kedify_envoysink_metrics_concurrent_set_total{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 31108
kedify_envoysink_metrics_flushes_processed_total{envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 104571
kedify_envoysink_metrics_rps_set_count{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 161
kedify_envoysink_metrics_rps_set_current{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 13371
kedify_envoysink_metrics_rps_set_total{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 1.943328e+06
kedify_envoysink_metrics_rps_zero_value_count{envoy_cluster_name="test",envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 281
kedify_envoysink_metrics_sessions_current{envoy_ip="10.42.0.16",stream_id="396c8eaf-4b49-4c20-92ab-4a08cc8ab9a6"} 1
```

Following these steps ensures that the `kedify-envoy-http` trigger correctly scales the deployment based on request rate.

