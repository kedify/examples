# WebSocket Server

This is a simple WebSocket server in Go deployable in Kubernetes. It exposes two HTTP paths:

```
http://websocket.keda/       - HTML website using JavaScript to connect to the WebSocket API
http://websocket.keda/echo   - WebSocket API for "ping/pong" messages
```

### Build and Push Images

To build and push the images run
```bash
make docker-build
make docker-push
```

### Deploy in k3d

This should work with a default k3d cluster and Traefik ingress controller

1. **Create the k3d Cluster**:

   ```bash
   k3d cluster create
   ```

2. **Deploy Server**:

   ```bash
   kubectl apply -f ./config/manifests.yaml
   ```

3. **Modify /etc/hosts**:
   
   Entry in `/etc/hosts` will ensure the [websocket.keda](websocket.keda) URL resolves to the `Ingress` assigned IP
   ```bash
   make patch-etc-hosts-file
   ```

4. **Test WebSocket in browser**:
   
   In your browser, go to [websocket.keda](websocket.keda) and follow the instructions there

5. **Enable Auto Scaling**:

   The WebSocket scale to zero is also supported.

   ```bash
   kubectl apply -f ./config/so.yaml
   ```
