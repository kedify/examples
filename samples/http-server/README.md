# HTTP Server

This is a simple HTTP server in Go designed for Kubernetes deployments. It accepts HTTP and HTTPS requests and responds accordingly while providing configurable response delays and exposing useful metrics for monitoring.

## Features

- **Configurable Response Delay**  
  The server supports an optional delay in responses. Set the `RESPONSE_DELAY` environment variable to introduce a delay:
  - **Fixed delay:** Set a single value (e.g., `"0.3"`) for a constant delay.
  - **Dynamic delay (range):** Set a range (e.g., `"1.5-3.7"`) to have the server randomly select a delay uniformly between the two values.

- **Endpoints**  
  The server exposes multiple endpoints:
  - `/`  
    Returns an HTML page with an image.
  - `/image`  
    Serves the image file.
  - `/echo`  
    Echoes back the incoming HTTP request (including headers and body) as plain text.
  - `/metrics`  
    Exposes Prometheus metrics:
    - **http_requests_total:** A counter that tracks the total number of requests per endpoint.
    - **response_delay_seconds:** A histogram capturing the distribution of response delays in seconds.


### Build and Push Images

To build and push the images run:
```bash
make docker-build
make docker-push
```

### Deploy in k3d

This setup works with a default k3d cluster and the Traefik ingress controller.

1. **Create the k3d Cluster**:

   ```bash
   k3d cluster create --port "9080:80@loadbalancer"
   ```

2. **Deploy Server**:

   ```bash
   kubectl apply -f ./config/manifests.yaml
   ```

3. **Configure Response Delay (Optional)**:

   The application can be configured to introduce a delay in its responses using the `RESPONSE_DELAY` environment variable. This can be set in the `manifests.yaml` file:

   ```yaml
   - name: RESPONSE_DELAY
     value: "0.3"
   ```
   This example introduces a 0.3-second delay in each response.

   ```yaml
   - name: RESPONSE_DELAY
     value: "0.5-10"
   ```
   This example introduces a random delay between 0.5 and 10 seconds.

4. **Test the HTTP Server**:

   You can test the server by specifying the host header and IP address and running `curl` command:

   ```bash
   curl -H 'host: demo.keda' http://localhost:9080
   ```

5. **Enable Autoscaling**:

   ```bash
   kubectl apply -f ./config/so.yaml
   ```

6. **Test Higher Load (to trigger autoscaling)**:

   ```bash
   hey -n 100000 -c 100 -host "demo.keda" http://localhost:9080
   ```

7. **Setup OTel Tracing** (optional):

   If you want to enable OpenTelemetry tracing, you can set the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable in your deployment manifest. This should point to your OpenTelemetry collector endpoint.

   ```yaml
   - name: OTEL_EXPORTER_OTLP_ENDPOINT
     value: "http://otel-collector:4317"
   ```

   Make sure you have an OpenTelemetry collector running in your cluster to receive the traces. Only the `/` root endpoint has tracing telemetry implemented.

8. **Simulating Errors**:

   You can simulate errors by setting the `ERROR_RATE` and `ERROR_RESP_CODE` environment variables. This will cause the server to randomly return HTTP 503 errors (or code specified by `ERROR_RESP_CODE`) based on the error rate.

   ```yaml
   - name: ERROR_RATE
     value: "0.1"  # 10% error rate
   - name: ERROR_RESP_CODE
     value: "500"  # HTTP status code to return on error
   ```

   This will cause approximately 10% of requests on endpoint `/error` to return a 500 Internal Server Error.

### Deploy in k3d with TLS and NGINX Ingress

You can run the HTTP server with TLS enabled behind the NGINX ingress controller using `TLS_ENABLED=true` and Kubernetes secrets for certificate management.

1. **Create a k3d Cluster with NGINX**:

  Create k3d cluster with disabled Traefik ingress controller:
  
  ```bash
  k3d cluster create --port "9080:80@loadbalancer" --port "9443:443@loadbalancer" --k3s-arg   "--disable=traefik@server:*"
  ```
  
  Install the NGINX ingress controller:
  
  ```bash
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  
  helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace nginx-ingress \
    --create-namespace \
    --set controller.publishService.enabled=true \
    --set controller.service.type=LoadBalancer
  ```

2. **Generate and Apply TLS Certificates**:

  For development, you can use self-signed certs:
  
  ```bash
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout certs/tls.key -out certs/tls.crt \
    -subj "/CN=tls-demo.keda/O=tls-demo.keda"
  
  kubectl create secret tls http-server-tls --cert=certs/tls.crt --key=certs/tls.key
  ```

3. **Deploy the Server with TLS Enabled**:

  Update your deployment to include:
  
  ```yaml
  - name: TLS_ENABLED
    value: "true"
  - name: TLS_CERT_FILE
    value: "/certs/tls.crt"
  - name: TLS_KEY_FILE
    value: "/certs/tls.key"
  ```
  
  Apply your deployment and ingress manifests:
  
  ```bash
  kubectl apply -f config/tls-manifests.yaml
  ```

3.1. **Configure TLS Delays** (Optional):

  It's possible to artificially introduce delays on the network layer for testing various scenarios with degraded network performance.

  ```yaml
  - name: TLS_ACCEPT_DELAY
    value: "2.0"
  - name: TLS_READ_DELAY
    value: "1.0"
  - name: TLS_WRITE_DELAY
    value: "0.5"
  - name: TLS_DELAY_TIMEOUT
    value: "5.0"
  ```

  These variables control the delays for accepting connections, reading from the connection, writing to the connection, and the expiration timeout for these operations.

4. **Test TLS with Host Header**:

  ```bash
  curl -H "Host: tls-demo.keda" -vk https://localhost:9443/
  ```

  **Note:** If you’re using self-signed certs you’ll need to tell `curl` to skip verification:

  ```bash
  curl -H "Host: tls-demo.keda" -k https://localhost:9443/
  ```

5. **Enable Autoscaling (TLS version)**:

  ```bash
  kubectl apply -f config/tls-so.yaml
  ```

6. **Test Higher Load (to trigger autoscaling)**:

  ```bash
  hey -n 100000 -c 100 -host "tls-demo.keda" https://localhost:9443/
  ```
