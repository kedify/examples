# Kedify Agent Without the HTTP Add-on

This example demonstrates the automatic `HTTPScaledObject` CRD detection introduced in Kedify Agent `v0.6.8`.

The agent hosts several controllers for the [Kedify HTTP Scaler](https://docs.kedify.io/scalers/http-scaler) (traffic autowiring, `EnvoyFleet`, `kedify-proxy` configuration). All of them watch the `HTTPScaledObject` custom resource, which only exists on clusters with the HTTP Add-on installed.

- **Before `v0.6.8`:** installing the agent on a cluster without the HTTP Add-on required setting `agent.rbac.manage.ingressAutoWire=false`, otherwise the agent would crashloop after ~2 minutes (informer cache sync timeout on the missing CRD).
- **Since `v0.6.8`:** the agent detects the missing CRD, starts without those controllers, and wires them automatically within seconds of the CRD appearing. No restart, no configuration changes.

The walkthrough below shows both halves of that behavior on a local [k3d](https://k3d.io) cluster.

## 1. Create a k3d Cluster

```bash
k3d cluster create kedify-crd-demo
```

## 2. Install the Kedify Agent (No HTTP Add-on)

The bundled [values.yaml](./values.yaml) installs the agent in offline mode with KEDA, but without the HTTP Add-on, so the `HTTPScaledObject` CRD is not present on the cluster.

```bash
helm repo add kedifykeda https://kedify.github.io/charts
helm repo update kedifykeda
helm upgrade --install kedify-agent kedifykeda/kedify-agent \
  --namespace keda --create-namespace \
  -f ./values.yaml
```

> **Note:** This example requires Kedify Agent `v0.6.8` or newer. On older versions, step 3 ends in a `CrashLoopBackOff` instead, which is exactly the behavior this feature removes.

## 3. Observe: No CRD, No Crash

Confirm the CRD is really absent and the agent deferred the HTTP Scaler controllers:

```bash
kubectl get crd httpscaledobjects.http.keda.sh
# Error from server (NotFound): customresourcedefinitions.apiextensions.k8s.io "httpscaledobjects.http.keda.sh" not found

kubectl logs -n keda deploy/kedify-agent | grep -i "HTTPScaledObject CRD"
# ... HTTPScaledObject CRD is not installed, the http-addon controllers will start once it is ...
```

The agent keeps polling the discovery API in the background with exponential backoff (1s doubling up to a 20s cap). Give it a few minutes to prove the point; the pod stays `Running` with zero restarts, where older versions would have crashed after the 2 minute cache sync timeout:

```bash
kubectl get pods -n keda -l control-plane=kedify-agent
# NAME                            READY   STATUS    RESTARTS   AGE
# kedify-agent-...                1/1     Running   0          5m
```

## 4. Install the HTTP Add-on

Install the Kedify HTTP Add-on, which brings the `HTTPScaledObject` CRD with it:

```bash
helm upgrade --install http-add-on kedifykeda/keda-add-ons-http --namespace keda
```

## 5. Observe: Controllers Start Automatically

Within at most 20 seconds (one backoff interval), the agent notices the CRD and starts the deferred controllers on the running process:

```bash
kubectl logs -n keda deploy/kedify-agent | grep crd-waiter
# ... crd-waiter ... the API is served now, starting the deferred controllers ...

kubectl logs -n keda deploy/kedify-agent | grep -i "Starting workers" | grep -i -e envoy -e httpscaledobject
```

The restart counter is still zero:

```bash
kubectl get pods -n keda -l control-plane=kedify-agent
```

From here the cluster is a regular Kedify installation with HTTP autoscaling; try the [http-server](../http-server) sample to scale an application from real traffic, including scale to zero.

## 6. Cleanup

```bash
k3d cluster delete kedify-crd-demo
```
