# Kubernetes rightsizing test workloads

Use these synthetic workloads to compare sizing advice in Kedify Insights,
PerfectScale, or other Kubernetes tooling. The manifests use standard Kubernetes
APIs and do not install a recommender or require a public endpoint.

```bash
kubectl apply -k test-data/rightsizing/cpu
kubectl -n rightsizing get pods
kubectl -n rightsizing top pods --containers
```

Allow for a CPU node with at least 4 vCPUs and 8 GiB for the lab and your
observability agents. The CPU workloads reuse the
[load-generator sample](../../samples/load-generator) at a pinned image digest.
CPU and memory settings are targets, so use measured usage when comparing tools.
The HPA and `kubectl top` need a working Kubernetes Metrics API.

| Workload | Signal to look for |
| --- | --- |
| `overprovisioned` | Steady CPU and memory usage well below requests. |
| `cpu-throttled` | Five-minute bursts capped at 350m despite a 900m target. Compare throttling and the CPU limit recommendation with `bursty-unthrottled`. |
| `bursty-unthrottled` | The same high-load profile with room to reach its CPU target. Look for recommendations that preserve headroom for bursts. |
| `mixed-containers` | Application memory usage exceeds its request while the idle nginx sidecar has oversized requests. Look for distinct per-container recommendations. |
| `startup-spike` | The same container starts on a 90-second CPU and memory spike, then drops to steady state. Use `kubectl -n rightsizing rollout restart deploy/startup-spike` to collect another startup sample. |
| `hpa-container` | A CPU utilization HPA scales to its two-replica cap using only the application container. Check whether a request change also changes the effective HPA target for that container. |
| `hpa-idle-floor` | A quiet workload stays at its two-replica minimum. Check for a minimum replica recommendation and whether it explains the availability tradeoff. |
| `missing-resources` | nginx has no requests or limits. Check for missing-resource findings and sensible initial values. |
| `memory-growth` | Retains 8 MiB more every five minutes for 3 hours 20 minutes, then holds. Check for sustained growth after warm-up and whether the tool avoids a premature limit reduction. Restart the Deployment to replay the ramp. |
| `short-batch` | A 45-second CronJob runs every 10 minutes. Check whether usage is collected and grouped across Job runs. |
| `memory-oom` | A CronJob intentionally exceeds its own 64 MiB memory limit twice an hour. Check for `OOMKilled` and a higher memory limit recommendation. |
| `mixed-containers` PDB | The only replica is protected from voluntary eviction by `minAvailable: 1`. Check whether the tool explains the drain blocker. |
| `unschedulable-selector` | A Pod intentionally stays Pending because its selector matches no node. Check for an explicit scheduling reason. |

Trigger the batch cases on demand with unique Job names. The memory Job is
expected to fail, and the pending fixture is expected to stay Pending. Actual
node consolidation needs at least two eligible nodes.

```bash
kubectl -n rightsizing create job --from=cronjob/short-batch short-batch-check
kubectl -n rightsizing create job --from=cronjob/memory-oom memory-oom-check
kubectl -n rightsizing get jobs,hpa,pdb
kubectl -n rightsizing get events --sort-by=.lastTimestamp
```

## Optional NVIDIA inference

This fixture reuses the [vLLM sample's model](../../samples/vllm-autoscaling).
It needs a node advertising `nvidia.com/gpu`, plus DCGM workload metrics for
GPU utilization and framebuffer memory. Verify that DCGM exposes
`DCGM_FI_DEV_GPU_UTIL` and `DCGM_FI_DEV_FB_USED`, and that total and driver-reserved
framebuffer memory are available for tools that use those as the denominator.
The Deployment defaults to zero replicas so CPU labs can keep the configuration
without reserving a GPU.

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

Observe an idle baseline first, then run the three-minute burst from inside the
cluster. Eight clients send requests while vLLM processes up to four sequences
at once, creating opportunities to observe queueing. The benchmark reports
completed tokens per second, p95 request latency, and errors. Use vLLM's `/metrics` for queue depth, KV cache utilization and time
to first token. Compare those with DCGM compute activity and framebuffer
allocation. vLLM preallocates KV cache, so GPU memory can stay allocated while
compute is idle.

```bash
kubectl -n rightsizing-gpu create job --from=cronjob/vllm-load vllm-load-check
kubectl -n rightsizing-gpu logs -f job/vllm-load-check
```

When done, scale the Deployment back to zero. If you added a dedicated GPU node
pool, scale that pool back down separately to stop billing for its nodes.

## Comparing results

Record the tool's observation window, sample coverage, current and suggested
requests and limits, reason, estimated savings, and any prerequisites for
applying the advice. Check usage and restart counts alongside recommendations.
Use the same cluster state and observation window when comparing two tools.
For Kedify Insights on a connected cluster with namespace opt-in enabled, label
the fixture namespaces:

```bash
kubectl label namespace rightsizing insights.kedify.io/scrape=true --overwrite
# If you applied the GPU fixture:
kubectl label namespace rightsizing-gpu insights.kedify.io/scrape=true --overwrite
```

For safe HPA replay, compare the effective CPU target in millicores before and
after changing application CPU requests. Leave the sidecar out of this
calculation because the HPA metric targets the application container.
