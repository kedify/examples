## Azul JVM & PodResourceProfiles

This example shows how PodResourceProfiles (vertical scaling) can help with resource intensive workloads during startup. Azul JVM - Zing runs JIT compilation during application warmup that dynamically 
optimize certain (hot) paths of code into machine code. This compilation process requires more CPU than normal mode of the Java application. At the same time, we would like to make sure,
the users get the best experience so that we should allow the incoming traffic to the application only after it has been heated and it is performant enough.

### Architecture

Azul JVM can expose the information about its compilation queue using JMX. With a simple Python script we can read this number and consider the workload ready only after it is bellow some configurable
threshold. Startup probes in Kubernetes are great fit for this use-case. They allow to check certain criteria more often during the startup and only after the startup is done, the classical readiness & liveness probes can kick in and start doing their periodic checks.

To demonstrate a Java application that does some serious heavy lifting, we choose to use the [Renaissance](https://renaissance.dev/) benchmarking suite from MIT. Namely the `finagle-http` benchmark. This particular benchmark 
sends many small Finagle HTTP requests to a Finagle HTTP server and waits for the responses. Once the benchmark run to completion, we run a sleep command.

> [!IMPORTANT]
> This feature is possible only with Kubernetes In-Place Pod Resource Updates. This feature is enabled by default since 1.33 (for older version it needs to be enabled using a feature flag).

### Demo

> [!TIP]
> For trying this on k3d, create the cluster using:
> ```bash
> k3d cluster create in-place-updates --no-lb --k3s-arg "--disable=traefik,servicelb@server:*" --k3s-arg "--kube-apiserver-arg=feature-gates=InPlacePodVerticalScaling=true@server:*"
> ```

1. Install Kedify in K8s cluster - https://docs.kedify.io/installation/helm
2. Deploy example application:

```bash
kubectl apply -f k8s/
```

3. Keep checking its CPU resources:

```bash
kubectl get po -lapp=heavy-workload -ojsonpath="{.items[*].spec.containers[?(.name=='main')].resources}" | jq
```

We should be able to see that after some time, it drops from `1` CPU to `0.2`.

In order to check the length of the compilation Q, one can run:
```bash
kubectl exec -ti $(kubectl get po -lapp=heavy-workload -ojsonpath="{.items[0].metadata.name}") -- /ready.py
JMX_HOST=127.0.0.1
JMX_PORT=9010
OUTSTANDING_COMPILES_THRESHOLD=500
786
TotalOutstandingCompiles still above threshold: 786 >= 500
command terminated with exit code 2
```

## Conclusion

By asking for right amount of compute power at right times, we allow for more effective bin-packing algorithm in Kubernetes and, if used together with tools like Karpenter, this boils down to real cost savings.
