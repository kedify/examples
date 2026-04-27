# Canary deployments with Argo Rollouts and `kedify-http`

This example shows how to combine Argo Rollouts canary strategy with the
`kedify-http` scaler. Traffic between the stable and canary versions is split
inside the Kedify interceptor (via Envoy `weighted_clusters`), driven by an
Argo Rollouts traffic router plugin (`kedify/http`) that patches an annotation
on the `HTTPScaledObject`.

## Prerequisites

- Kubernetes cluster
- An Ingress controller that publishes an external address on the `Ingress`
  status (e.g. a `LoadBalancer` IP or hostname). `make patch-etc-hosts-file`
  waits on `.status.loadBalancer.ingress[]` to be populated and won't proceed
  without it
- KEDA + Kedify (HTTP add-on) installed, with the Kedify agent running
- [Argo Rollouts](https://argoproj.github.io/argo-rollouts/installation/) installed
  with the `kedify/http` traffic router plugin loaded. The plugin ships as
  pre-built binaries on
  [its GitHub releases](https://github.com/kedify/argo-rollouts-plugin/releases) - 
  copy the install snippet (with the matching `sha256` from `checksums.txt`)
  into the `argo-rollouts-config` ConfigMap in the `argo-rollouts` namespace
  and restart the controller
- [`kubectl argo rollouts`](https://argoproj.github.io/argo-rollouts/installation/#kubectl-plugin-installation)
  plugin - used below to drive the canary (`set image`, `promote`,
  `abort`, `status`). If you'd rather not install it, you can drive the
  Rollout via plain `kubectl patch` against the Rollout spec/status instead
- **Cluster-admin permission** to apply the sample - `make deploy` creates a
  `ClusterRole`/`ClusterRoleBinding` granting the Argo Rollouts controller
  patch access to `HTTPScaledObject` resources cluster-wide
- The sample assumes Argo Rollouts is installed in namespace `argo-rollouts`
  and runs as the `argo-rollouts` ServiceAccount (the upstream defaults). If
  you've installed it elsewhere, adjust the `subjects:` namespace + name in
  `manifests.yaml` accordingly

## Architecture

```
Argo Rollouts → kedify/http plugin SetWeight(N)
   ↓ patches
HTTPScaledObject annotation: http.kedify.io/weighted-backends
   ↓ observed by
Kedify interceptor → Envoy WeightedClusters {stable: 100-N%, canary: N%}
   ↓
kedify-proxy splits traffic between stable / canary services
```

The Argo Rollout owns the pod template, canary strategy, and service wiring.
When the `ScaledObject` is active, KEDA/HPA manages the Rollout's replica
count via the Rollout `/scale` subresource. The `ScaledObject` targets the
Rollout (`apiVersion: argoproj.io/v1alpha1, kind: Rollout`) - the scaler
resolves `stableService` / `canaryService` from the Rollout spec
automatically, so no `service` field is required in trigger metadata.

## Deploy

```
make deploy
```

This creates:

- `Rollout/rollouts-demo` with stable image `argoproj/rollouts-demo:blue`, `stableService: rollouts-demo-stable`, `canaryService: rollouts-demo-canary`,
  and explicit canary weights of 20% / 50% / 80%, then full promotion on completion
- `Service/rollouts-demo-stable`, `Service/rollouts-demo-canary` (selector managed by Argo Rollouts)
- `Ingress/rollouts-demo` pointing at the stable service - autowire will rewrite the backend to `kedify-proxy`
- `ScaledObject/rollouts-demo` with a `kedify-http` trigger; no `service` is specified - the scaler auto-resolves it from the Rollout

```
$ kubectl get rollout,httpso,so
NAME                                DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
rollout.argoproj.io/rollouts-demo   2         2         2            2           21s

NAME                                          TARGETWORKLOAD   TARGETSERVICE   MINREPLICAS   MAXREPLICAS   AGE   ACTIVE
httpscaledobject.http.keda.sh/rollouts-demo                                    2             5             20s

NAME                                 SCALETARGETKIND                SCALETARGETNAME   MIN   MAX   READY   ACTIVE    FALLBACK   PAUSED   TRIGGERS      AUTHENTICATIONS   AGE
scaledobject.keda.sh/rollouts-demo   argoproj.io/v1alpha1.Rollout   rollouts-demo     2     5     True    Unknown   False      False    kedify-http                     21s
```

## Test the application

Set the host alias for `demo.keda`:

```
make patch-etc-hosts-file
```

Send some traffic. Initially everything goes to the stable (`blue`) version:

```
$ for i in {1..10}; do curl -s http://demo.keda/color; echo; done
"blue"
"blue"
...
```

## Trigger a canary

Switch the canary image to `yellow`:

```
kubectl argo rollouts set image rollouts-demo rollouts-demo=argoproj/rollouts-demo:yellow
```

Argo Rollouts moves to step 1 (`setWeight: 20`). The plugin patches the
`HTTPScaledObject` annotation:

```
$ kubectl get httpso rollouts-demo -o jsonpath='{.metadata.annotations.http\.kedify\.io/weighted-backends}'
- service: rollouts-demo-stable
  weight: 80
- service: rollouts-demo-canary
  weight: 20
```

Send traffic - roughly 20% should now hit `yellow`:

```
$ for i in {1..50}; do curl -s http://demo.keda/color; echo; done | sort | uniq -c
     41 "blue"
      9 "yellow"
```

Continue through the remaining steps:

```
kubectl argo rollouts promote rollouts-demo
```

Watch the rollout progress with:

```
kubectl argo rollouts get rollout rollouts-demo --watch
```

When the canary fully promotes, the plugin removes the `http.kedify.io/weighted-backends` annotation and the interceptor reverts to a
single cluster pointing at the stable service (now serving the new image).

To roll back mid-canary:

```
kubectl argo rollouts abort rollouts-demo
```

## Cleanup

```
kubectl delete -f manifests.yaml
```

## Further reading

- [Argo Rollouts canary strategy](https://argoproj.github.io/argo-rollouts/features/canary/)
- [Argo Rollouts traffic management plugins](https://argoproj.github.io/argo-rollouts/features/traffic-management/plugins/)
- Kedify Argo Rollouts plugin source: <https://github.com/kedify/argo-rollouts-plugin>
