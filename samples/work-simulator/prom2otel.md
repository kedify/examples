# Mitration from Prometheus Scaler to OTel Scaler

This is a step-by-step tutorial about migrating previous setup (check [Step-by-Step KEDA Guide](./guide.md) & 
[Application Details](./app.md)) and turn it into OTel collector + OTel scaler setup.

## Why

Check our [blog post](https://kedify.io/resources/blog/using-otel-collector-with-keda) that describes some of the reasoning. We can also check the resource consumption of 
Prometheus stack:

```
kubectl top pod -n monitoring
NAME                                                        CPU(cores)   MEMORY(bytes)
alertmanager-kube-prometheus-stack-alertmanager-0           2m           36Mi
kube-prometheus-stack-grafana-cdd5bbc47-zh7qc               18m          273Mi
kube-prometheus-stack-kube-state-metrics-67b7fc84dc-p8n42   2m           21Mi
kube-prometheus-stack-operator-c8d96c4d6-q57wc              2m           32Mi
kube-prometheus-stack-prometheus-node-exporter-khlxv        4m           10Mi
prometheus-kube-prometheus-stack-prometheus-0               16m          300Mi
```

These numbers will, unfortunately, only go higher.

### Pause the ScaledObject

This step is optional, but it would prevent some errors in KEDA operator logs.

```
kubectl annotate so work-simulator-scaledobject --overwrite autoscaling.keda.sh/paused=true
```

### Uninstall the Prometheus

We want the OTel collector to be scraping the metrics from our `work-simulator` app and sending them to KEDA OTel Scaler.
In this setup we don't need the Prometheus stack anymore, although Grafana for instance can be also used together with the OTel collector.

```
kubectl delete -f config/servicemonitor.yaml
helm uninstall kube-prometheus-stack -n monitoring
```

### Install the KEDA OTel Scaler and OTel Collector

Helm Chart for KEDA OTel Scaler can install and configure also the OTel Collector. To do that run the following command:

```
helm upgrade --install kedify-otel oci://ghcr.io/kedify/charts/otel-add-on --version=v0.0.5 -nkeda -f config/otel-scaler-values.yaml
```

If you inspect the helm chart values, it contains the configuration for OTel collector. It consist of four main sections:
- receivers
- (processors)
- exporters
- (extensions)
- services

We won't be using any processors, so this section is missing. There is one exporter that sends the metric data into our
KEDA Scaler. This is the part responsible for evaluating the PromQL query later on. Under the services section all the 
previously mentioned and configured components needs to be enabled.

For our purposes we will be using one receiver (Prometheus). Not to be mistaken, it's not a Prometheus server, but rather it's
part responsible for scraping the metrics. It has the same configuration style as full blown Prometheus config so one can 
define static targets or dynamic scrape configs there ([receiver-docs](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md) & [promconfig-docs](https://github.com/prometheus/prometheus/blob/v2.28.1/docs/configuration/configuration.md#scrape_config)).

This part of the configuration is important because it describes how the metric data is obtained. By using the Prometheus 
receiver, we opted to use the pull model, but we could have also instrumented our `work-simulator` with OTel sdk and send the 
metric data, together with logs and traces, into OTel collector - push model.

As for Prometheus CRDs (`PodMonitor` and `ServiceMonitor`), we can use the OTel Collector Operator together with their
`TargetAllocator` [CRD](https://github.com/open-telemetry/opentelemetry-operator/blob/main/cmd/otel-allocator/README.md) [nice blogpost](https://opentelemetry.io/blog/2024/prom-and-otel/#using-the-target-allocator). However, the OTel Scaler doesn't support the operator at the moment so let's achieve the same goal with dynamic scrape target.
That is the

```yaml
              kubernetes_sd_configs:
                - role: pod
              relabel_configs:
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                  regex: "true"
                  action: keep
```
part in the Prometheus receiver's config. It will be collecting metrics from all pods that have annotation called `prometheus.io/scrape: "true"` on them. So let us add the annotation on the deployment's pod template:

```
kubectl patch deploy work-simulator --type=merge -p '{"spec":{"template": {"metadata":{"annotations": {"prometheus.io/scrape":"true"}}}}}'

# optionally, we can also remove such annotation from a traefik pod to mitigate the noise in the logs (k3d specific)
kubectl patch deploy traefik -nkube-system --type=merge -p '{"spec":{"template": {"metadata":{"annotations": {"prometheus.io/scrape":"false"}}}}}'
```

### Migrate the ScaledObject

When using the Prometheus scaler as a trigger for the ScaledObject (SO), it has slightly different fields under the metadata section.
To migrate from it to another scaler, apply this SO, this will also unpause it, because the annotation that pauses the ScaledObject is not present:

```
kubectl apply -f config/so-otel.yaml

# generate some load and also populate the missing metrics in the `work-simulator` app's metric endpoint
kubectl delete job load-generator && kubectl apply -f ./config/load.yaml

# if you paused the SO before
kubectl annotate so work-simulator-scaledobject --overwrite autoscaling.keda.sh/paused=false
```

### Verification

From now on, you can continue by creating some load, same steps as in - [original-tutoial](./guide.md#3-generate-load-to-test-autoscaling).
