# Autoscaling of Application Based on Business Logic Metrics from Prometheus

This guide describes how to autoscale an application using KEDA on Kubernetes. The application is scaled based on business logic metrics (ie., the amount of "work" being processed) collected by a Prometheus instance deployed via the Prometheus Operator. The `work-simulator` application simulates tasks, exposing Prometheus metrics that reflect in-progress work. 

If there is no workload, the application scales down to 1 replica. As the amount of work increases, the number of replicas can scale up to a defined maximum (e.g., 10 replicas). This method ensures efficient resource utilization based on real business logic rather than simple traffic metrics.

The Prometheus KEDA scaler is used for this setup. For more details, refer to the [KEDA Prometheus Scaler Documentation](https://keda.sh/docs/latest/scalers/prometheus/).

---

## 0. Install KEDA and Prometheus Stack

1. **Install KEDA**  
   Use the simple one-command installation method provided by Kedify for quick and reliable KEDA setup. Follow the [Kedify Quickstart](https://kedify.io/documentation/getting-started/quickstart#step-1-install-kedify-agent).

2. **Install Prometheus Stack**  
   Deploy the Prometheus stack using the Prometheus Operator. The following Helm commands will install Prometheus, Alertmanager, Grafana, and associated components:

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
   ```

   Verify that Prometheus and related components are running:

   ```bash
   kubectl get pods -n monitoring
   ```

   You should see running pods for Prometheus, Alertmanager, and Grafana.

---

## 1. Deploy Application that Exposes Prometheus Metrics

Deploy the `work-simulator` application, which exposes Prometheus metrics for business logic. The required manifests are located in the `config/` directory.

Apply the `work-simulator` deployment and service:

```bash
kubectl apply -f config/manifests.yaml
```

This will deploy the application and expose it on port 8080. Verify the application is running by checking the logs:

```bash
kubectl logs deployment/work-simulator
```

The output should be similar to:

```bash
2025/01/24 21:15:53 Using min sleep: 100ms, max sleep: 600ms
2025/01/24 21:15:53 work-simulator running on port 8080
```

Deploy the `ServiceMonitor` to configure Prometheus scraping:

```bash
kubectl apply -f config/servicemonitor.yaml
```

You can verify the metrics are correctly scraped by locating the new target in Prometheus UI. First we will port forward the proper service and then access it on http://localhost:9090.

```bash
kubectl port-forward service/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```

---

## 2. Deploy ScaledObject for Autoscaling

Create a `ScaledObject` to define the scaling behavior. The required manifest is located in the `config/so.yaml` file. Apply it to enable autoscaling:

```bash
kubectl apply -f config/so.yaml
```

Verify the `ScaledObject`:

```bash
kubectl get scaledobject work-simulator-scaledobject
```

You should see an output where `READY` is `True`.

---

## 3. Generate Load to Test Autoscaling

### Option 1: Kubernetes Job

Simulate load using a Kubernetes Job. The job runs an image with `hey` tool to generate HTTP requests.

Apply the job:

```bash
kubectl apply -f load.yaml
```

Monitor the scaling behavior:

```bash
watch kubectl get deployment work-simulator
```

### Option 2: Port Forward and Generate Load Locally

Alternatively, you can generate load locally by forwarding the application port to your machine and using either `curl` or `hey`:

1. Port forward the service:

   ```bash
   kubectl port-forward service/work-simulator 8080:8080
   ```

2. Use `hey` to generate load:

   ```bash
   hey -z 2m -c 50 http://localhost:8080/work
   ```

   - **`-z 2m`**: Number of minutes that we will send requests.
   - **`-c 50`**: Number of concurrent workers.

   Or use a simple `curl` :

   ```bash
   curl -s http://localhost:8080/work
   ```

Monitor the scaling behavior:

```bash
watch kubectl get deployment work-simulator
```

You should see the number of replicas increase as load is applied. Once the load is processed, the replicas will scale back down to 1.

---

## 4. Clean Up

To clean up the resources created during this guide, run the following commands:

```bash
kubectl delete jobs load-generator
kubectl delete -f config/so.yaml
kubectl delete -f config/servicemonitor.yaml
kubectl delete -f config/manifests.yaml
```
