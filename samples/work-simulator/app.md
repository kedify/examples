# Work Simulator

This is a simple work simulator application in Go, deployable in Kubernetes. The application accepts HTTP requests on the `/work` endpoint, simulates processing tasks with configurable delays, and exposes Prometheus metrics for monitoring and autoscaling.

---

## Build and Push Images

To build and push the Docker images, run:

```bash
make docker-build
make docker-push
```

- **`make docker-build`**: Builds the Docker image locally.
- **`make docker-push`**: Builds and pushes the Docker image to the container registry for multiple architectures.

Ensure you have Docker installed and are authenticated with your container registry (e.g., GitHub Container Registry).

---

## Deploy in k3d

This setup works with a default k3d cluster and the Traefik ingress controller.

### 1. Create the k3d Cluster

Create a new k3d cluster and map port `8080` of your local machine to port `8080` of the cluster's load balancer:

```bash
k3d cluster create work-simulator-cluster --port "8080:8080@loadbalancer"
```

### 2. Deploy Work Simulator

Apply the Kubernetes manifests to deploy the `work-simulator` application:

```bash
kubectl apply -f ./config/manifests.yaml
```

### 3. Configure Sleep Duration (Optional)

The application can be configured to set minimum and maximum sleep durations using the `MIN_SLEEP_MS` and `MAX_SLEEP_MS` environment variables. These are set in the `work-simulator-deployment.yaml` file:

```yaml
env:
  - name: MIN_SLEEP_MS
    value: "100"   # Minimum sleep duration in milliseconds
  - name: MAX_SLEEP_MS
    value: "600"   # Maximum sleep duration in milliseconds
```

Adjust these values as needed to simulate different workloads.

### 4. Access the Application via Port Forward

To interact with the `work-simulator` application from your local machine, use `kubectl port-forward`:

```bash
kubectl port-forward service/work-simulator 8080:8080
```

This command forwards your local port `8080` to the `work-simulator` service's port `8080`. You can now send HTTP requests to `http://localhost:8080/work`.

### 5. Test the Work Simulator

Send a request to the `/work` endpoint:

```bash
curl http://localhost:8080/work
```

**Expected Response:**
```
Completed work in 350 ms
```

Each request to `/work` will simulate a task by sleeping for a random duration between the configured `MIN_SLEEP_MS` and `MAX_SLEEP_MS`.

### 6. Enable Autoscaling

To enable autoscaling with KEDA based on the `work_simulator_inprogress_tasks` metric, apply the `ScaledObject` manifest:

```bash
kubectl apply -f ./config/so.yaml
```

Ensure that Prometheus is configured to scrape the `/metrics` endpoint of your `work-simulator` service. If you're using the Prometheus Operator, you might need to create a `ServiceMonitor` resource as well:

```bash
kubectl apply -f ./config/servicemonitor.yaml
```

### 7. Test Higher Load (to Trigger Autoscaling)

Use a load testing tool like `hey` to generate load and trigger autoscaling:

```bash
hey -n 2000 -c 100 http://localhost:8080/work
```

- **```-n 2000```**: Number of requests to send.
- **```-c 100```**: Number of concurrent workers.

This command sends 2,000 requests with 100 concurrent workers to the `/work` endpoint, simulating significant load and prompting KEDA to scale the application based on the in-progress tasks metric.

---

## Accessing Prometheus Metrics

Prometheus scrapes the `/metrics` endpoint to collect metrics:

- **```work_simulator_requests_total```**: Total number of `/work` requests received.
- **```work_simulator_inprogress_tasks```**: Number of tasks currently being processed.

To view the metrics locally, run:

```bash
curl http://localhost:8080/metrics
```

**Sample Metrics Output:**
```
HELP work_simulator_requests_total Total number of /work requests received by work-simulator

TYPE work_simulator_requests_total counter

work_simulator_requests_total 5

HELP work_simulator_inprogress_tasks Number of tasks currently being processed by work-simulator

TYPE work_simulator_inprogress_tasks gauge

work_simulator_inprogress_tasks 0
```
---

## Monitoring and Autoscaling with KEDA

To set up autoscaling with KEDA based on the `work_simulator_inprogress_tasks` metric:

1. **Ensure Prometheus is Scraping Metrics**:

    If using the Prometheus Operator, apply a `ServiceMonitor`:

    ```bash
    kubectl apply -f ./config/servicemonitor.yaml
    ```

2. **Apply the KEDA `ScaledObject`**:

    The `ScaledObject` defines how KEDA should scale the `work-simulator` Deployment based on Prometheus metrics.

    ```yaml
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: work-simulator-scaledobject
      namespace: default
    spec:
      scaleTargetRef:
        kind: Deployment
        name: work-simulator
      minReplicaCount: 1
      maxReplicaCount: 10
      triggers:
        - type: prometheus
          metadata:
            serverAddress: http://prometheus-operated.monitoring.svc.cluster.local  # Update with your Prometheus service address
            metricName: work_simulator_inprogress_tasks
            query: sum(work_simulator_inprogress_tasks)
            threshold: "10"
    ```

    Apply the `ScaledObject`:

    ```bash
    kubectl apply -f ./config/so.yaml
    ```

    **Note**: Adjust `serverAddress` to match your Prometheus service endpoint.
