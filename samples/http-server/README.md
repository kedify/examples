# HTTP Server

This is a simple HTTP server in Go designed for Kubernetes deployments. It accepts HTTP requests and responds accordingly while providing configurable response delays and exposing useful metrics for monitoring.

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
   hey -n 200000 -c 100 -host "demo.keda" http://localhost:9080
   ```
