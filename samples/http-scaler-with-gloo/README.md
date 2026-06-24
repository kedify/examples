# Kedify HTTP Scaler with Gloo Gateway

This example shows how to autoscale an HTTP application exposed through
[Gloo Gateway](https://docs.solo.io/gloo-edge/latest/) using the `kedify-http`
scaler and traffic autowiring.

Kedify watches the Gloo `VirtualService`, delegated `RouteTable`, or `Upstream`
that points at the scaled service and rewrites the route to `kedify-proxy`.
Traffic then flows through Kedify so requests are measured and the target
deployment can scale from zero.

The manifests in this sample use Gloo Edge resources from `gateway.solo.io/v1`
and `gloo.solo.io/v1`. Kedify also supports Gloo Mesh/Gateway v2
`networking.gloo.solo.io/v2` `RouteTable` resources when their destinations
point directly to a Kubernetes `SERVICE` or to a `VIRTUAL_DESTINATION` backed by
the scaled Kubernetes Service.

## Prerequisites

- Kubernetes cluster
- Kedify installed with HTTP Scaler enabled
- Gloo Gateway installed

For a local test cluster, install Gloo Gateway with a LoadBalancer gateway proxy:

```bash
kubectl create namespace gloo-system
helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update gloo
helm upgrade --install gloo gloo/gloo \
  --version 1.21.9 \
  --namespace gloo-system \
  --values ./manifests/gloo-values.yaml \
  --wait
```

On local arm64 clusters, if `gateway-proxy` fails with `Failed to create
temporary file`, mount a writable `/tmp` and wait for the rollout:

```bash
kubectl -n gloo-system patch deployment gateway-proxy --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"tmp","emptyDir":{}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"tmp","mountPath":"/tmp"}}]'
kubectl -n gloo-system rollout status deployment/gateway-proxy --timeout=180s
```

## Deploy Sample Application

```bash
kubectl apply -f ./manifests/app.yaml
```

The sample starts with zero replicas. The KEDA `ScaledObject` uses the
`kedify-http` trigger with `trafficAutowire: gloo` so KEDA creates the matching
`HTTPScaledObject` and Kedify can autowire the Gloo route.

```bash
kubectl get deployments,svc,httpscaledobjects,scaledobjects
```

## Choose a Gloo Route Shape

Apply one of these route examples:

```bash
# Direct VirtualService route to a Kubernetes service
kubectl apply -f ./manifests/virtualservice.yaml

# VirtualService delegating to a RouteTable
kubectl apply -f ./manifests/routetable.yaml

# VirtualService route through a Gloo Upstream
kubectl apply -f ./manifests/upstream.yaml
```

All three route shapes expose the application on `gloo-http.keda`.

If you apply or change the Gloo route after the generated `HTTPScaledObject`
already exists, touch the `HTTPScaledObject` so Kedify reconciles the new route:

```bash
kubectl annotate httpscaledobject http-server \
  kedify.io/reconcile="$(date +%s)" --overwrite
```

## Test Autoscaling

From inside the cluster, call the Gloo gateway:

```bash
kubectl run curl --image=curlimages/curl:8.10.1 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/curl --timeout=120s
kubectl exec curl -- curl -i -H "host: gloo-http.keda" \
  http://gateway-proxy.gloo-system.svc.cluster.local/
```

From outside the cluster, use the external address published on the Gloo gateway
service:

```bash
GLOO_GATEWAY=$(kubectl -n gloo-system get svc gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')
curl -i -H "Host: gloo-http.keda" "http://$GLOO_GATEWAY/"
```

For local k3d clusters, publish the load balancer port when creating the
cluster, for example `k3d cluster create --port "9080:80@loadbalancer"`, then
call through localhost:

```bash
curl -i -H "Host: gloo-http.keda" http://localhost:9080/
```

For existing k3d clusters with a host port mapped to a node port, expose the
Gloo gateway as `NodePort`. For example, with `8181:31198@loadbalancer`
published:

```bash
kubectl -n gloo-system patch svc gateway-proxy --type=json \
  -p='[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"add","path":"/spec/ports/0/nodePort","value":31198}]'
curl -i -H "Host: gloo-http.keda" http://localhost:8181/
```

If your local cluster does not publish a load balancer port, use `kubectl
port-forward` as a fallback:

```bash
kubectl -n gloo-system port-forward svc/gateway-proxy 9080:80
curl -i -H "Host: gloo-http.keda" http://localhost:9080/
```

After the first request, the application should scale out:

```bash
kubectl get deployment http-server
```

When traffic stops, Kedify scales it back to zero after the configured cooldown
period.

## Demo a Custom Cold-Start Waiting Page

The `waiting-page-demo.yaml` manifest creates a separate copy of the sample app
so it can run next to the basic `http-server` example:

- `Deployment/http-server-waiting`
- `Service/http-server-waiting`
- `ScaledObject/http-server-waiting`
- `ConfigMap/http-server-waiting-page`
- `VirtualService/http-server-waiting`

The waiting-page demo is exposed on `gloo-waiting.keda`. It sets
`STARTUP_DELAY=20` on the app container and uses a TCP readiness probe, so the
pod stays unready until the HTTP server actually starts listening. During that
cold start, Kedify serves the configured waiting page immediately and keeps the
HTTP metrics needed to scale the deployment.

```bash
kubectl apply -f ./manifests/waiting-page-demo.yaml
```

From outside the cluster:

```bash
GLOO_GATEWAY=$(kubectl -n gloo-system get svc gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')
curl -i -H "Host: gloo-waiting.keda" "http://$GLOO_GATEWAY/"
```

The first response should be the custom waiting page with
`503 Service Unavailable` and a `Retry-After: 3s` header. Retry after the app
finishes its startup delay and the same URL should return the normal sample
application.

To watch the cold start and later scale-to-zero:

```bash
kubectl get deployment http-server-waiting pods -w
```

If you change the route after the generated `HTTPScaledObject` already exists,
touch that object so Kedify reconciles the Gloo route again:

```bash
kubectl annotate httpscaledobject http-server-waiting \
  kedify.io/reconcile="$(date +%s)" --overwrite
```
