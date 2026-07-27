# Scaling an Agones Fleet with KEDA via ScaleAdapter

This example demonstrates `ScaleAdapter` (`autoscaling.kedify.io/v1alpha1`), available starting with Kedify Agent `v0.6.8`, on a local [k3d](https://k3d.io) cluster with a real [Agones](https://agones.dev) game server Fleet.

An Agones `Fleet` exposes a writable `/scale` subresource, but its `Scale` object has an empty `status.selector` ([agones#2051](https://github.com/googleforgames/agones/issues/2051), wontfix). The HPA controller rejects such a target with `InvalidSelector` before evaluating any metric, so a KEDA `ScaledObject` pointed directly at a Fleet never scales. The `ScaleAdapter` sits in between: it exposes a complete `/scale` (replicas plus an explicit Pod selector) and forwards replica changes to the Fleet. See the [ScaleAdapter documentation](https://docs.kedify.io/features/scale-adapter) for details.

The walkthrough first reproduces the broken direct path, then fixes it with the adapter, scales up, down to zero, back up, and finally demonstrates the single-writer conflict handling.

## 1. Create a k3d Cluster and Install Agones

```bash
k3d cluster create agones-demo

helm repo add agones https://agones.dev/chart/stable
helm repo update agones
helm install agones agones/agones --namespace agones-system --create-namespace
```

By default Agones allows `GameServer` Pods in the `default` namespace, which is where this example runs. If you move the Fleet elsewhere, add `--set "gameservers.namespaces={<your-namespace>}"`.

## 2. Install the Kedify Agent with ScaleAdapter Enabled

The bundled [values.yaml](./values.yaml) installs the agent in offline mode with KEDA, enables the ScaleAdapter controller (`agent.features.scaleAdaptersEnabled=true`), and grants the one extra permission it needs: `fleets/scale`.

```bash
helm repo add kedifykeda https://kedify.github.io/charts
helm repo update kedifykeda
helm upgrade --install kedify-agent kedifykeda/kedify-agent \
  --namespace keda --create-namespace \
  -f ./values.yaml
```

## 3. Deploy the Fleet

```bash
kubectl apply -f ./fleet.yaml
kubectl get fleet game-fleet -w
# wait until READY shows 2
```

Note the label in [fleet.yaml](./fleet.yaml) sits on the inner Pod template (`spec.template.spec.template.metadata.labels`). Labels on the GameServer template would land on `GameServer` objects instead of Pods, and the adapter's selector would match nothing.

## 4. Reproduce the Problem (Optional but Instructive)

Point a `ScaledObject` directly at the Fleet and watch the generated HPA refuse to work:

```bash
kubectl apply -f ./so-direct.yaml
kubectl get hpa keda-hpa-game-fleet-direct \
  -o jsonpath='{range .status.conditions[?(@.type=="ScalingActive")]}{.status} {.reason}: {.message}{end}'; echo
# False InvalidSelector: ... the server could not properly convert the selector ...
```

No metric is ever evaluated. Clean it up before the next step:

```bash
kubectl delete -f ./so-direct.yaml
```

## 5. Fix It with a ScaleAdapter

Create the adapter and a `ScaledObject` that targets the adapter instead of the Fleet. The trigger is a `kubernetes-resource` scaler reading a value from a ConfigMap, so you can drive scaling deterministically with `kubectl patch`:

```bash
kubectl apply -f ./scale-adapter.yaml
kubectl get sca game-fleet
# NAME         ... check Ready=True in status.conditions

kubectl apply -f ./so.yaml
```

The demand ConfigMap starts at `2`, and with `targetValue: "1"` the fleet settles at 2 replicas.

## 6. Scale Up, Down to Zero, and Back

```bash
# scale up: demand 6 -> 6 game servers
kubectl patch configmap game-demand --type merge -p '{"data":{"value":"6"}}'
kubectl get fleet game-fleet -w

# scale to zero: demand 0 -> fleet drains after the 30s cooldown
kubectl patch configmap game-demand --type merge -p '{"data":{"value":"0"}}'

# reactivate from zero: KEDA writes to the adapter directly for 0->1 activation
kubectl patch configmap game-demand --type merge -p '{"data":{"value":"3"}}'
```

Scale-up reacts within one KEDA polling interval (30s by default); scale-in additionally waits for the HPA stabilization window.

## 7. Single Writer: Conflict Handling

Exactly one component may own the Fleet's desired replicas. Try to fight the adapter:

```bash
kubectl scale fleet game-fleet --replicas=9
```

Within one sync interval (15s) the adapter overwrites the manual change back to the autoscaled value and leaves an audit trail:

```bash
kubectl get events --field-selector reason=ExternalReplicaChange
```

For the same reason, do not combine the adapter with an Agones `FleetAutoscaler` on the same Fleet.

## 8. Cleanup

```bash
k3d cluster delete agones-demo
```
