# KEDA http-add-on with Istio

This example serves as a guide on how to use KEDA + http-add-on to autoscale applications based on HTTP traffic along with Istio.

As a prerequisite, you will need a Kubernetes cluster with istio. Could be any istio supported Kubernetes distribution, for [example k3d](https://istio.io/latest/docs/setup/platform-setup/k3d/).
For the purpose of this walkthrough example, all three `istio-base`, `istiod`, and `istio-ingressgateway` are necessary.
```
$ kubectl create ns istio-system

$ helm repo add istio https://istio-release.storage.googleapis.com/charts
$ helm repo update

$ helm install istio-base istio/base -n istio-system --wait
$ helm install istiod istio/istiod -n istio-system --wait
$ helm install istio-ingressgateway istio/gateway -n istio-system --wait
```

##### Step 1: Prepare istio sidecar injection
At the time of writing the tutorial, istio ambient mesh is still in [alpha status](https://istio.io/v1.19/docs/ops/ambient/getting-started/) so we will continue with the sidecar istio.
The application is going to be deployed in `default` `Namespace` and KEDA will be in `keda` `Namespace`, let's enable it for all pods in these namespaces.

```
$ kubectl create ns keda
$ kubectl patch namespace keda -p '{"metadata": {"labels": {"istio-injection": "enabled"}}}'
$ kubectl patch namespace default -p '{"metadata": {"labels": {"istio-injection": "enabled"}}}'
```

##### Step 2: Deploy KEDA

Because istio is already enabled on the entire `keda` `Namespace`, sidecars will be automatically injected.
```
$ helm repo add kedacore https://kedacore.github.io/charts
$ helm install keda kedacore/keda --namespace keda
$ helm install http-add-on kedacore/keda-add-ons-http --namespace keda
```

There should be KEDA now installed and running together with http-add-on
```
$ kubectl get po -nkeda
NAME                                                    READY   STATUS    RESTARTS   AGE
keda-add-ons-http-controller-manager-79db447c7d-7r9xb   3/3     Running   0          39s
keda-add-ons-http-external-scaler-dfb9f7bcc-dxqft       2/2     Running   0          39s
keda-add-ons-http-external-scaler-dfb9f7bcc-fh76m       2/2     Running   0          39s
keda-add-ons-http-external-scaler-dfb9f7bcc-phcw9       2/2     Running   0          39s
keda-add-ons-http-interceptor-6dd68bbc87-5jz6v          2/2     Running   0          38s
keda-add-ons-http-interceptor-6dd68bbc87-5ng2w          2/2     Running   0          39s
keda-add-ons-http-interceptor-6dd68bbc87-pnp47          2/2     Running   0          38s
keda-admission-webhooks-554fc8d77f-n7mml                2/2     Running   0          39s
keda-operator-dd878ddf6-7ww29                           2/2     Running   0          39s
keda-operator-metrics-apiserver-86cc9c6fff-t4prd        2/2     Running   0          39s
```

##### Step 3: Deploy sample application

[Podinfo](https://github.com/stefanprodan/podinfo) is a great testing application, we will use it here because it's small, simple to use and
simple to inspect. Its output ca provide helpful insight into the `Pod` internals.
```
$ helm upgrade --install --wait podinfo --namespace default oci://ghcr.io/stefanprodan/charts/podinfo
```

Let's expose it using istio `VirtualService`.
```
$ kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/samples/http-add-on_with_istio/manifests/istio.yaml
```

Your application should be now available on the istio gateway IP address under host www.podinfo.com.
```
$ GATEWAY_IP=$(kubectl get svc -nistio-system istio-ingressgateway -o json | jq --raw-output '.status.loadBalancer.ingress[0].ip')
$ curl -H "host: www.podinfo.com" "http://$GATEWAY_IP"
```
```json
{
  "hostname": "podinfo-5965fc9856-4tfpg",
  "version": "6.6.3",
  "revision": "b0c487c6b217bed8e6a53fca25f6ee1a7dd573e3",
  "color": "#34577c",
  "logo": "https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/cuddle_clap.gif",
  "message": "greetings from podinfo v6.6.3",
  "goos": "linux",
  "goarch": "amd64",
  "runtime": "go1.22.3",
  "num_goroutine": "8",
  "num_cpu": "16"
}
```

The `podinfo` is running in `default` `Namespace` with the istio sidecar injected and operational.
```
$ kubectl get po -ndefault
NAME                       READY   STATUS    RESTARTS   AGE
podinfo-5965fc9856-4tfpg   2/2     Running   0          22s
```

##### Step 4: Start autoscaling

First we will need to create `HTTPScaledObject` to tell KEDA and http-add-on what metrics to use and which `Deployment` to scale
```
$ kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/samples/http-add-on_with_istio/manifests/httpscaledobject.yaml
```

Because the minimal replica count in the `HTTPScaledObject` you should see the `Deployment` scale to 0 instantly.
```
$ kubectl get deployments -ndefault
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
podinfo   0/0     0            0           2m
```

As a second step, we need to reconfigure the istio `VirtualService` to pass the traffic first to http-add-on which then routes
the traffic to `podinfo` application.

```
$ kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/samples/http-add-on_with_istio/manifests/virtualservice_through_keda.yaml
```

When querying the `podinfo` now, there is going to be additional delay in the response coming from the cold start of the first `Pod`
```
$ time curl -H "host: www.podinfo.com" "http://$GATEWAY_IP"
{
  "hostname": "podinfo-5965fc9856-vlddc",
  "version": "6.6.3",
  "revision": "b0c487c6b217bed8e6a53fca25f6ee1a7dd573e3",
  "color": "#34577c",
  "logo": "https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/cuddle_clap.gif",
  "message": "greetings from podinfo v6.6.3",
  "goos": "linux",
  "goarch": "amd64",
  "runtime": "go1.22.3",
  "num_goroutine": "8",
  "num_cpu": "16"
}
real    0m3.553s
user    0m0.008s
sys     0m0.004s
```
The `interceptor` caches the request for `podinfo` and releases it as soon as the first `Pod` is available to handle the traffic.

##### Istio `NetworkPolicies`

`NetworkPolicies` are frequently used together with istio service mesh. Given application traffic used in the KEDA http based scaling must flow
through the http-add-on's `interceptor`, depending on your policies, you may need to enable this network path explicitly.

For KEDA `interceptor` egress rules
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-interceptor
  namespace: keda
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: interceptor
      app.kubernetes.io/instance: http-add-on
      app.kubernetes.io/part-of: keda-add-ons-http
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          istio-injection: enabled
      podSelector:
        matchLabels:
          app.kubernetes.io/name: podinfo
    ports:
    - port: 9898
  policyTypes:
  - Egress
```
And or for application ingress rules
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-keda
  namespace: default
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: podinfo
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          istio-injection: enabled
    ports:
    - protocol: TCP
      port: 9898
  policyTypes:
  - Ingress
```
