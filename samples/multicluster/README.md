# Multi-cluster Scaling

This example demonstrates how to set up a multi-cluster environment using k3d and scale applications based on custom metrics using Kedify. The setup includes one KEDA k3d cluster and three member k3d clusters, running an instance of a sample application workload. KEDA is configured to monitor a mock metric and scale the application pods accordingly across the member fleet.

### Setup

1. **Create KEDA Cluster and Install Kedify**:

For the purposes of this demo, you can use k3d. This cluster will host KEDA from Kedify and for easier organization between all the clusters we are going to be using, you can put the kubeconfig in a temporary location:
```bash
KUBECONFIG=/tmp/keda-cluster k3d cluster create keda-cluster
```

Install Kedify version at least v0.4.0 - see https://docs.kedify.io/getting-started/quickstart

2. **Create Member Clusters**:

Create three member clusters that will host the sample application workload:
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/member-cluster-$i k3d cluster create k3d-member-$i --api-port 6550$i --k3s-arg "--tls-san=host.k3d.internal@server:*"
done
```

3. **Deploy Sample Application**:

Deploy a sample application (in this case nginx web server) to each member cluster:
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/member-cluster-$i kubectl create deployment nginx --image=nginx
done
```

Each deployment will start with a single replica.
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/member-cluster-$i kubectl get deployments
done
```

4. **Register Member Clusters with Kedify**:

Register each member cluster with the Kedify instance running in the KEDA cluster. This allows KEDA to manage and scale workloads across these clusters. You will need kedify CLI plugin for kubectl installed - see https://docs.kedify.io/features/kubectl-kedify-plugin
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/keda-cluster kubectl kedify mc setup-member k3d-member-$i --keda-kubeconfig /tmp/keda-cluster --member-kubeconfig /tmp/member-cluster-$i --member-api-url https://host.k3d.internal:6550$i
done
```

You can list the registered member clusters using:
```bash
KUBECONFIG=/tmp/keda-cluster kubectl kedify mc list-members
```

5. **Configure Multi-cluster Scaling**:

In the KEDA cluster, create a `DistributedScaledObject` that references the deployments in the member clusters. We are going to use `kubernetes-resource` trigger type to scale based on a mock metric stored in a `ConfigMap` because this is very convenient for demonstrating the multi-cluster scaling properties.
Below is an example YAML configuration, this will be applied to the KEDA cluster which will perform the scaling across the member clusters:

```bash
cat <<EOF | KUBECONFIG=/tmp/keda-cluster kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mock-metric
data:
  metric-value: "20"
---
apiVersion: keda.kedify.io/v1alpha1
kind: DistributedScaledObject
metadata:
  name: nginx
spec:
  scaledObjectSpec:
    scaleTargetRef:
      kind: Deployment
      name: nginx
    minReplicaCount: 1
    maxReplicaCount: 10
    triggers:
    - type: kubernetes-resource
      metadata:
        resourceKind: ConfigMap
        resourceName: mock-metric
        key: metric-value
        targetValue: "5"
EOF
```

6. **Check Scaling**:

The `DistributedScaledObject` takes scaling actions as soon as it is created. You can monitor the scaling activity by checking the number of replicas in each member cluster:
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/member-cluster-$i kubectl get deployment nginx
done
```

You can also inspect the `DistributedScaledObject` status to see information about scaling decisions:
```bash
KUBECONFIG=/tmp/keda-cluster kubectl describe distributedscaledobject nginx
```

Changing the value in the `ConfigMap` will trigger scaling actions. For example, to scale up the deployments, you can set the metric value higher:
```bash
cat <<EOF | KUBECONFIG=/tmp/keda-cluster kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mock-metric
data:
  metric-value: "50"
EOF
```

Shortly after applying the above change, you should see the deployments in the member clusters scale up accordingly:
```bash
for i in 1 2 3; do
  KUBECONFIG=/tmp/member-cluster-$i kubectl get deployment nginx
done
```

7. **Outage Simulation and Rebalancing**:

To simulate a member cluster outage, you can delete the nginx deployment from one of the member clusters:
```bash
KUBECONFIG=/tmp/member-cluster-2 kubectl delete deployment nginx
```

KEDA will detect this and wait for a grace period (configurable, with default as 1 minute) before rebalancing the workload across the remaining member clusters. You can monitor the status of the `DistributedScaledObject` to see when rebalancing occurs:
```bash
KUBECONFIG=/tmp/keda-cluster kubectl describe distributedscaledobject nginx
```

You can simulate restoring the member cluster by redeploying nginx:
```bash
KUBECONFIG=/tmp/member-cluster-2 kubectl create deployment nginx --image=nginx
```

A bigger outage can be simulated by deleting an entire member cluster:
```bash
k3d cluster delete k3d-member-3
```

KEDA will again wait for the grace period before rebalancing the workload across the remaining member clusters. Monitor the status as before.
```bash
KUBECONFIG=/tmp/keda-cluster kubectl describe distributedscaledobject nginx
```

If you know that this member cluster will be down for an extended period (or permanently), you can also unregister it from Kedify to avoid unnecessary errors:
```bash
KUBECONFIG=/tmp/keda-cluster kubectl kedify mc delete-member k3d-member-3
```

8. **Whitelisting Members and Scaling Weights**:

You can control which member clusters are eligible for scaling using whitelisting. You can also assign different scaling weights to each member cluster to influence how the workload is distributed.
To update the `DistributedScaledObject` to whitelist specific members and set scaling weights, you can modify it as follows:
```bash
cat <<EOF | KUBECONFIG=/tmp/keda-cluster kubectl apply -f -
apiVersion: keda.kedify.io/v1alpha1
kind: DistributedScaledObject
metadata:
  name: nginx
spec:
  memberClusters:
  - name: k3d-member-1
    weight: 3
  - name: k3d-member-2
    weight: 1
  scaledObjectSpec:
    scaleTargetRef:
      kind: Deployment
      name: nginx
    minReplicaCount: 1
    maxReplicaCount: 10
    triggers:
    - type: kubernetes-resource
      metadata:
        resourceKind: ConfigMap
        resourceName: mock-metric
        key: metric-value
        targetValue: "5"
EOF
```

9. **Scale Jobs with DistributedScaledJob resource**:

You can also use `DistributedScaledJob` to scale jobs across multiple clusters. This example demonstrates how to use kubernetes resource triggers to schedule job scaling across member clusters:

```bash
cat <<EOF | KUBECONFIG=/tmp/keda-cluster kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mock-metric
data:
  metric-value: "20"
---
kind: DistributedScaledJob
apiVersion: keda.kedify.io/v1alpha1
metadata:
  name: dsj-example
spec:
  memberClusters:
    - name: k3d-member-1
    - name: k3d-member-2
  scaledJobSpec:
    minReplicaCount: 0
    maxReplicaCount: 10
    pollingInterval: 10
    rollout:
      propagationPolicy: foreground
      strategy: gradual
    successfulJobsHistoryLimit: 2
    failedJobsHistoryLimit: 2
    triggers:
    - type: kubernetes-resource
      metadata:
        resourceKind: ConfigMap
        resourceName: mock-metric
        key: metric-value
        targetValue: "5"
    jobTargetRef:
      activeDeadlineSeconds: 96000
      backoffLimit: 0
      completions: 1
      parallelism: 1
      template:
        spec:
          containers:
          - name: busybox
            imagePullPolicy: IfNotPresent
            image: busybox
            command: ["sh", "-c", "echo 'Hello from busybox' && sleep 33"]
          restartPolicy: Never
EOF
```

The `DistributedScaledJob` will create and manage jobs across the specified member clusters based on the kubernetes resource triggers. You can monitor the jobs in each member cluster:
```bash
for i in 1 2; do
  KUBECONFIG=/tmp/member-cluster-$i kubectl get jobs
done
```
