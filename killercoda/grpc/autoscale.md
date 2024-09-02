Using Kedify to scale your application based on gRPC traffic works pretty much the same as with regular HTTP traffic and is as simple as creating one Kubernetes manifest, `ScaledObject`{{}}.

> If you are new to KEDA, you can read more about `ScaledObject`{{}} in the official docs https://keda.sh/docs/2.15/reference/scaledobject-spec

The `ScaledObject`{{}} references the desired application and configures scaling parameters so KEDA knows how to scale it.
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: grpc-responder
  namespace: default
spec:
  maxReplicaCount: 5
  minReplicaCount: 0
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 5
  cooldownPeriod: 5
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: grpc-responder
  triggers:
  - metadata:
      hosts: grpc.keda
      pathPrefixes: /
      port: "50051"
      scalingMetric: requestRate
      service: grpc-responder
      targetValue: "10"
      tlsSecretName: grpc-responder
    metricType: AverageValue
    type: kedify-http
EOF
```{{exec}}

Lets take a look at the fields to better understand what will happen next:
* `scaleTargetRef`{{}} - references the application `Deployment`{{}} "grpc-responder" deployed earlier
* `minReplicaCount`{{}} - allows scaling to 0 when there is no traffic flowing to the application
* `maxReplicaCount`{{}} - capping maximum number of `Pods`{{}} to 5
* `triggers.type`{{}} - the `kedify-http`{{}} is a [Kedify HTTP scaler](https://kedify.io/scalers/http)
* `triggers.metadata.hosts`{{}} - domain `grpc.keda`{{}} is matching the domain also configured in the `Ingress`{{}}
* `triggers.metadata.scalingMetric`{{}} - metric `requestRate`{{}} triggers scaling by default based on the number of requests per second
* `triggers.metadata.targetValue`{{}} - value `10`{{}} means that for each 10 requests per second, there will be a replica of the application
* `triggers.metadata.tlsSecretName`{{}} - reference to a `Secret`{{}} containing TLS cert/key pair for end-to-end traffic encryption

As soon as the `ScaledObject`{{}} is created, the Kedify agent autowiring will modify the application `Ingress`{{}} to route the requests through KEDA. This is achieved by lazily deploying `kedify-proxy`{{}} in the application namespace.

```
kubectl wait -ndefault --timeout=5m --for=condition=Available deployment/kedify-proxy
kubectl wait -ndefault --timeout=5m --for=jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}="kedify-proxy"' ingress/grpc-responder
kubectl get -ndefault ingress grpc-responder -o json | jq '.spec.rules[].http.paths[].backend'
```{{exec}}

The `backend`{{}} referenced in the application `Ingress`{{}} is no longer `"grpc-responder"`{{}} but `"kedify-proxy"`{{}} instead. This means the network traffic is routed there first and then back to the application.

> The `kedify-proxy`{{}} forms an [envoy proxy](https://www.envoyproxy.io/) fleet deployed/undeployed and configured dynamically by Kedify. It also forwards live metrics to KEDA for scaling. When using scale to 0, there is also one instance of centrally deployed reverse proxy called `interceptor`{{}}. This `interceptor`{{}} is a component from [HTTP Add-on](https://github.com/kedacore/http-add-on) used for caching requests during application cold starts.

You can observe the scaling metrics directly from KEDA using `kubectl`{{}}
```bash
kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq '.'
```{{exec}}

Right now you should see that our configured metric `RPS`{{}} is `0`{{}}, that is because we made no requests to the application since it has been configured for autoscaling.
```json
{
  "default/grpc-responder": {
    "Concurrency": 0,
    "RPS": 0
  }
}
```{{}}

There is a convenience benchmark script that can help you visualize scale-out and scale-in based on the number of requests flowing through KEDA.
```
/scripts/benchmark.sh
```{{exec}}

Whenever you are done with your observations, you can close the script with:
```
# ctrl+c
```{{exec interrupt}}

Congratulations! You have successfully configured gRPC autoscaling using Kedify, you can learn more about Kedify and check out our other courses at [https://kedify.io/tutorials](https://kedify.io/tutorials).

&nbsp;
&nbsp;

##### 4 / 4
