Using Kedify to scale your application based on HTTP traffic is as simple as creating one Kubernetes manifest, `ScaledObject`{{}}.

> If you are new to KEDA, you can read more about `ScaledObject`{{}} in the official docs https://keda.sh/docs/2.15/reference/scaledobject-spec

The `ScaledObject`{{}} references the desired application and configures scaling parameters so KEDA knows how to scale it.
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: blue 
  namespace: default
spec:
  maxReplicaCount: 5
  minReplicaCount: 0
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: blue
  triggers:
  - metadata:
      hosts: blue.com
      pathPrefixes: /
      port: "8080"
      scalingMetric: requestRate
      service: blue
      targetValue: "10"
    metricType: AverageValue
    type: kedify-http
EOF
```{{exec}}

Lets take a look at the fields to better understand what will happen next:
* `scaleTargetRef`{{}} - references the application `Deployment`{{}} "blue" deployed earlier
* `minReplicaCount`{{}} - allows scaling to 0 when there is no traffic flowing to the application
* `maxReplicaCount`{{}} - capping maximum number of `Pods`{{}} to 5
* `triggers.type`{{}} - the `kedify-http`{{}} is a [Kedify HTTP scaler](https://kedify.io/scalers/http)
* `triggers.metadata.hosts`{{}} - domain `blue.com`{{}} is matching the domain also configured in the `Ingress`{{}}
* `triggers.metadata.scalingMetric`{{}} - metric `requestRate`{{}} triggers scaling by default based on the number of requests per second
* `triggers.metadata.targetValue`{{}} - value `10`{{}} means that for each 10 requests per second, there will be a replica of the application

As soon as the `ScaledObject`{{}} is created, the Kedify agent autowiring will modify the application `Ingress`{{}} to route the requests through KEDA. This is achieved by lazily deploying `kedify-proxy`{{}} in the application namespace.

```
kubectl wait -ndefault --timeout=5m --for=condition=Available deployment/kedify-proxy
kubectl wait -ndefault --timeout=5m --for=jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}="kedify-proxy"' ingress/blue
kubectl get -ndefault ingress blue -o json | jq '.spec.rules[].http.paths[].backend'
```{{exec}}

The `backend`{{}} referenced in the application `Ingress`{{}} is no longer `"blue"`{{}} but `"kedify-proxy"`{{}} instead. This means the network traffic is routed there first and then back to the application.

> The `kedify-proxy`{{}} forms an [envoy proxy](https://www.envoyproxy.io/) fleet deployed/undeployed and configured dynamically by Kedify. It also forwards live metrics to KEDA for scaling. When using scale to 0, there is also one instance of centrally deployed reverse proxy called `interceptor`{{}}. This `interceptor`{{}} is a component from [HTTP Add-on](https://github.com/kedacore/http-add-on) used for caching requests during application cold starts.

You can observe the scaling metrics directly from KEDA using `kubectl`{{}}
```bash
kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq '.'
```{{exec}}

Right now you should see that our configured metric `RPS`{{}} is `0`{{}}, that is because we made no requests to the application since it has been configured for autoscaling.
```json
{
  "default/demo": {
    "Concurrency": 0,
    "RPS": 0
  }
}
```{{}}

Let's run a few requests with `curl`{{}} and see if the metric changes
```bash
for i in $(seq 1 20); do curl http://blue.com; done
```{{exec}}
```bash
kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq '.'
```{{exec}}

Before the benchmark, we will make the KEDA behaviour more rapid, both scaling in and scaling out. This is unlikely something you'd want in a production environment, but it is helpful in demos and when testing KEDA behaviour.
```
kubectl patch scaledobject blue -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleDown":{"stabilizationWindowSeconds": 5}}}}}}'
kubectl patch scaledobject blue -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleUp":{"stabilizationWindowSeconds": 1}}}}}}'
kubectl patch scaledobject blue -n default --type=merge -p='{"spec":{"cooldownPeriod": 5}}'
```{{exec}}

To observe the metric changing in real time, you can run following benchmark script running [`hey`{{}}](https://github.com/rakyll/hey) under the hood:
```bash
/scripts/benchmark.sh
```{{exec}}

In order to stop the benchmark, hit:
```
# ctrl+c
```{{exec interrupt}}

Congratulations! You have successfully configured HTTP autoscaling using Kedify, you can learn more about Kedify and check out our other courses at:
* https://kedify.io
* https://killercoda.com/kedify/course/killercoda

&nbsp;
&nbsp;

##### 4 / 4
