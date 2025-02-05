# ScalingGroups

This is an example usage of a kedify `ScalingGroup` feature to enforce a limit on scaling shared among a group of `ScaledObjects`.

Currently, the feature is guarded by feature flag, to enable this set following env var on a `keda-operator`.
```
$ kubectl --namespace=keda set env deployment/keda-operator KEDIFY_ENABLED_SCALINGGROUPS=true
```

### Basic Group Capacity

There is an example of a `ScalingGroup`, you can deploy it to your cluster
```
$ kubectl apply -f scalinggroup.yaml
```

The controller for scaling groups should populate the status, currently there are no `ScaledObjects` matching the defined selector
so the status should look similar to this:
```
$ kubectl get sg
NAME        CAPACITY   RESIDUALCAPACITY   MEMBERCOUNT
max-group   2          2                  0
```

Provided are two applications with `ScaledObject` that match the group selector, both applications use `kubernetes-workload` scaler
which makes arbitrary scaling for testing easily possible. Lets deploy first one
```
$ kubectl apply -f so1.yaml
```
There are now two `Deployments` with one `Pod` each and a single `ScaledObject`
```
$ kubectl get deployments
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
app-1                1/1     1            1           10s
test-keda-metric-1   1/1     1            1           10s

$ kubectl get scaledobject
NAME    SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED    TRIGGERS   AUTHENTICATIONS   AGE
app-1   apps/v1.Deployment   app-1             0     10    True    True     False      Unknown                                11s
```
The `Deployment` with name `app-1` is scaled by `app-1` `ScaledObject` which has a metric source number of `Pods` in `test-keda-metric-1`
mock `Deployment`. When `test-keda-metric-1` is scaled to higher replica count, `HPA` will also try to scale `app-1` to the matching replica
count.

The controller for scaling groups will adjust the `ScalingGroup` status
```
$ kubectl get sg
NAME        CAPACITY   RESIDUALCAPACITY   MEMBERCOUNT
max-group   2          1                  1
```

At this point there is no need to cap any metrics because the total sum of replicas across all member `ScaledObjects` is below
the group capacity. We can try to change that with increasing the underlying metric source for the `ScaledObject`
```
$ kubectl scale deployment test-keda-metric-1 --replicas=5
```

Without the scaling group in place, this would result in `app-1` scaled to 5 replicas as well, but because capacity for the `max-group`
is 2, the `app-1` won't be allowed to scale past that.

```
$ kubectl get deployments
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
app-1                2/2     2            2           19s
test-keda-metric-1   5/5     5            5           19s
```

There is going to be an event regarding the metric cap on the `ScaledObject`
```
$ kubectl describe so | grep sg-metrics-processor
...
Events:
  Type    Reason                    Age   From                        Message
  ----    ------                    ----  ----                        -------
  Normal  AddedToScalingGroup       24s   sg-scaledobject-controller  ScaledObject added to ScalingGroup max-group
  Normal  KEDAScalersStarted        24s   keda-operator               Scaler kubernetes-workload is built.
  Normal  KEDAScalersStarted        24s   keda-operator               Started scalers watch
  Normal  ScaledObjectReady         24s   keda-operator               ScaledObject is ready for scaling
  Normal  KEDAScaleTargetActivated  24s   keda-operator               Scaled apps/v1.Deployment default/app-1 from 0 to 1, triggered by kubernetesWorkloadScaler
  Normal  MetricsCapped             17s   sg-metrics-processor        Metrics capped: [s0-workload-default(5 => 2)] due to ScalingGroup max-group
```
There are well known events from `keda-operator` and also two new. One from `sg-scaledobject-controller` regarding `ScaledObject` being
added to a group and second from `sg-metrics-processor` about metric being capped to satisfy group capacity.

### Overprovisioning Recovery

Now when the group is at max capacity, adding a new `ScaledObject` would result in overprovisioning. There is a built in algorithm to
gradually and eventually decrease metrics for `ScaledObjects` in the overprovisioned group to try to satisfy the group capacity.

Lets create second autoscaled application, it is a mirror of the `app-1`, similar deployments, similar scaling triggers, only called `app-2`.
```
$ kubectl apply -f so2.yaml
```
The group will become overprovisioned as soon as the HPA status is populated
```
$ kubectl get sg -w
NAME        CAPACITY   RESIDUALCAPACITY   MEMBERCOUNT
max-group   2          0                  1
max-group   2          0                  2
max-group   2          -1                 2
```
The `RESIDUALCAPACITY` of a group is calculated as `CAPACITY` minus sum of all `HPA` desired replica counts as reported in the status.
After this instance, there is an overprovisioning recovery algorithm that will report even lower than the capped metric with some probability.
There are a few rules that apply:
* each `ScaledObject` can be capped at most down to the specified `minReplicaCount`, never below
* larger overprovisioning results in higher probability a `ScaledObject` will be capped more
* if sum of `minReplicaCount` across all `ScaledObjects` is larger than group capacity, the group will remain overprovisioned

At some point, the group will stabilize without overprovisioning, because scaling group can satisfy all requirements
```
$ kubectl get sg -w
NAME        CAPACITY   RESIDUALCAPACITY   MEMBERCOUNT
max-group   2          0                  2

$ kubectl get deployments.apps
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
app-1                1/1     1            1           1m
app-2                1/1     1            1           21s
test-keda-metric-1   5/5     5            5           1m
test-keda-metric-2   1/1     1            1           21s
```

### Dynamic Increase of Group Capacity
If we adjust the group capacity to a higher number, member `ScaledObjects` will be allowed to scale higher
```
$ kubectl patch sg max-group --type=merge --patch='{"spec":{"capacity":10}}'
```
Let's observe how group status changes
```
$ kubectl get sg -w
NAME        CAPACITY   RESIDUALCAPACITY   MEMBERCOUNT
max-group   10         8                  2
max-group   10         4                  2
```
The `app-1` is no longer capped and can scale out to what the underlying metric is reporting
```
$ kubectl get deployments.apps
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
app-1                5/5     5            5           2m
app-2                1/1     1            1           1m
test-keda-metric-1   5/5     5            5           2m
test-keda-metric-2   1/1     1            1           1m
```
