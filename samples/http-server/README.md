# HTTP Server

This is a simple HTTP server in Go deployable in Kubernetes. The server accepts HTTP requests and responds accordingly. It also supports an optional delay in response, configurable via an environment variable.

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
