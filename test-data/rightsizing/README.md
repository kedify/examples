# Kubernetes rightsizing test workloads

Use these synthetic workloads to compare sizing advice in Kedify Insights,
PerfectScale, or other Kubernetes tooling. The manifests use standard Kubernetes
APIs and do not install a recommender or require a public endpoint.

```bash
kubectl apply -k test-data/rightsizing/cpu
kubectl -n rightsizing get pods
kubectl -n rightsizing top pods --containers
```

Allow about 4 vCPUs and 8 GiB of allocatable capacity for the lab and your
observability agents. The CPU workloads reuse the
[load-generator sample](../../samples/load-generator) at a pinned image digest.
CPU and memory settings are targets, so use measured usage when comparing tools.

| Workload | Signal to look for |
| --- | --- |
| `overprovisioned` | Steady CPU and memory usage well below requests. |
| `cpu-throttled` | Five-minute bursts capped at 350m despite a 900m target. Compare throttling and the CPU limit recommendation with `bursty-unthrottled`. |
| `bursty-unthrottled` | The same high-load profile with room to reach its CPU target. Look for recommendations that preserve headroom for bursts. |
| `mixed-containers` | Application memory usage exceeds its request while the idle nginx sidecar has oversized requests. Look for distinct per-container recommendations. |

## Optional NVIDIA inference

This fixture reuses the [vLLM sample's model](../../samples/vllm-autoscaling).
It needs a node advertising `nvidia.com/gpu`, plus DCGM workload metrics for
GPU utilization and framebuffer memory. It defaults to zero replicas so CPU
labs can keep the configuration without reserving a GPU.

```bash
kubectl apply -k test-data/rightsizing/gpu
kubectl -n rightsizing-gpu scale deployment/vllm --replicas=1
kubectl -n rightsizing-gpu rollout status deployment/vllm --timeout=15m
kubectl -n rightsizing-gpu port-forward svc/vllm 8000:8000
```

In a second terminal, send a completion request.

```bash
curl -fsS http://localhost:8000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"opt125m","prompt":"The capital of France is","max_tokens":32}'
```

Compare compute activity with framebuffer allocation while idle and under load.
vLLM preallocates KV cache, so GPU memory use can stay high while compute is idle.
When done, scale the Deployment back to zero. If you added a dedicated GPU node
pool, scale that pool back down separately to stop billing for its nodes.

## Comparing results

Record the tool's observation window, sample coverage, current and suggested
requests and limits, reason, estimated savings, and any prerequisites for
applying the advice. Check usage and restart counts alongside recommendations.
Use the same cluster state and observation window when comparing two tools.
