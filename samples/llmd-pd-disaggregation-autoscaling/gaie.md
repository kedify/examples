# Basic setup (getting started)
[GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/deploy-gke-inference-gateway#prepare-environment)
[GAIE](https://gateway-api-inference-extension.sigs.k8s.io/guides/)

# Install CRDs
To get the inferencepools and inferenceobjectives CRDs

```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/latest/download/manifests.yaml
```

# Create the Gateway

```
kubectl apply -f - << EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
spec:
  gatewayClassName: gke-l7-regional-external-managed
  listeners:
    - protocol: HTTP
      port: 80
      name: http
EOF
```

# Custom GKE resources
There are some custom resources needed for GKE, we use the ones generated from the helmchart [GAIE](https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/main/config/charts/inferencepool/values.yaml), the resource is `HealthCheckPolicy`.

The error `no healthy upstream` should be solved by this. The gateway need to have a healthy backends. And test default endpoints, with this we set where the gateway checks for models health. For vllm is on port 8000 and /health endpoint. 
**NOTE**: Please ensure the necessary healtchecks are properly set for wichever gateway implementation you use.


```
# Source: inferencepool/templates/gke.yaml
kubectl apply -f - << EOF
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: igw-vllm-health
  namespace: default
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: pd-llm-d-modelservice
  default:
    # Set a more aggressive health check than the default 5s for faster switch
    # over during EPP rollout.
    timeoutSec: 2
    checkIntervalSec: 2
    config:
      type: HTTP
      httpHealthCheck:
          requestPath: /health
          port:  8000
EOF
```

# To generate the file

You can use the healthcheck provided earlier, in case you need to generate it use the following:

```
helm template prod-stack-vllm-facebook-opt-125m \
  --set 'inferencePool.modelServers.matchLabels.llm-d\.ai/model=pd-llm-d-modelservice' \
  --set provider.name=gke \
  --set inferenceExtension.monitoring.gke.enabled=false \
  --version v1.0.1 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool -f inferencepoolhelmvalues.yaml
```