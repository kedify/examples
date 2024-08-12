As mentioned previously, in this scenario, you will have a `ScaledObject`{{}} per backend deployment version, here is a matching one for `prpl`{{}}
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: prpl 
  namespace: default
spec:
  maxReplicaCount: 5
  minReplicaCount: 0
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prpl
  triggers:
  - metadata:
      hosts: prpl
      pathPrefixes: /
      port: "8080"
      scalingMetric: requestRate
      service: prpl
      targetValue: "1"
    metricType: AverageValue
    type: kedify-http
EOF

# with making KEDA more rapid for prpl too
kubectl patch scaledobject prpl -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleDown":{"stabilizationWindowSeconds": 5}}}}}}'
kubectl patch scaledobject prpl -n default --type=merge -p='{"spec":{"advanced":{"horizontalPodAutoscalerConfig":{"behavior":{"scaleUp":{"stabilizationWindowSeconds": 1}}}}}}'
kubectl patch scaledobject prpl -n default --type=merge -p='{"spec":{"cooldownPeriod": 5}}'
```{{exec}}

Because now requests for both backend versions have the same domain and path, it is important to configure modifiers on each rule filter so KEDA knows how to differentiate requests passing through the `kedify-proxy`{{}} for `blue`{{}} and `prpl`{{}}. The details are encapsulated in `/scripts/envoy.yaml`{{}}, feel free to check it.

```
kubectl apply -f /scripts/envoy.yaml
```{{exec}}

> Envoy Gateway currently supports only header modifiers while HTTTP Add-on doesn't have header based routing, so request modifiers with metric counting is temporarily little more involved. The header based routing is on a roadmap for next HTTP scaler release which will simplify this setup a great deal.

When you observe the scaling metrics directly from KEDA using `kubectl`{{}}, there should be both backend versions
```bash
kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq '.'
```{{exec}}

The `blue`{{}} probably still has some `RPS`{{}}, but `prpl`{{}} should be `0`
```json
{
  "default/blue": {
    "Concurrency": 0,
    "RPS": 7.841
  },
  "default/prpl": {
    "Concurrency": 0,
    "RPS": 0
  }
}
```{{}}

And now with the benchmark script, both versions should be autoscaled.
```bash
/scripts/benchmark.sh
```{{exec}}

In order to stop the benchmark, hit:
```
# ctrl+c
```{{exec interrupt}}

Gateway API allows dynamically adjusting what portion of the traffic should be forwarded to which version. Let's make 90% of the traffic go to `blue`{{}} and only 10% to `prpl`{{}}:
```
kubectl patch httproute app -n default --type=json -p='[{"op": "replace", "path": "/spec/rules/0/backendRefs/0/weight", "value": 9}]'
kubectl get httproute app -n default -o json | jq '.spec.rules[].backendRefs[].weight'
```{{exec}}

The numbers `9`{{}} and `1`{{}} are appropriate weights for the loadbalancing algorithm. To observe the changes, run the benchmark again
```
/scripts/benchmark.sh
```{{exec}}

Congratulations! You have successfully configured HTTP autoscaling using Kedify, you can learn more about Kedify and check out our other courses at [https://kedify.io/tutorials](https://kedify.io/tutorials).

&nbsp;
&nbsp;

##### 5 / 5
