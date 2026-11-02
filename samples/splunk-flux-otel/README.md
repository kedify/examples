# Flux, Splunk OTel and record-only Predictor

This sample deploys a Flux-managed autoscaling demo on AKS. It was migrated from
the standalone `splunk-flux-otel` demo. From the repository root, enter the sample
directory before running the commands below:

```sh
cd samples/splunk-flux-otel
```

Traffic → HAProxy → nginx. Splunk's bundled single cluster collector scrapes each HAProxy pod at port 1024. The shared receiver feeds `metrics/haproxy` → Splunk and `metrics/scaling` → OTel Scaler over OTLP/gRPC. Existing Splunk node/cluster monitoring pipelines remain intact.

KEDA queries the scaler and drives nginx's HPA. Predictor independently subscribes to KEDA's TLS raw-metrics stream and stores RPS measurements in PostgreSQL. **The ScaledObject never queries Predictor.** Training readiness is not required for recording.

## Versions and ownership

| Component | Pin | Namespace |
|---|---|---|
| AKS | 1.35.8, two Standard_D2s_v5 nodes | mobility-global / West Europe |
| Flux | 2.10.0 | flux-system |
| HAProxy chart / controller | 1.47.3 / 3.2.3 | ingress-system |
| Splunk chart / Collector | 0.120.0 | observability |
| Kedify KEDA | v2.20.0-1 | keda |
| Kedify Agent | v0.8.3 | keda |
| OTel Scaler | 0.1.5 | keda |
| Predictor | 0.1.9 | keda |
| PostgreSQL | 17.11, digest pinned | keda |

These are the versions used for the original verification on 2026-10-29. The demo retains the `mobility-global` cluster/context name and uses Azure's `managed-csi` storage class.

All releases and workload configuration are owned by Flux. Agent auto-updates are disabled and optional Agent subcharts are disabled. Bootstrap installs only Flux and initial trust material outside GitOps. Generated HPA resources belong to KEDA; nginx's replica field is omitted from Git. PostgreSQL uses an 8Gi `managed-csi` disk. PVC history is retained across pod replacement.

Predictor stores uploaded model files on a dedicated 1Gi `managed-csi` PVC mounted at `/models`. PostgreSQL remains the database; `noSharedVolumes: true` prevents the chart from creating its SQLite PVC. Training jobs use temporary model storage and upload to the API. The API pod uses `fsGroup: 65532` for write access and a `Recreate` deployment strategy for its single-node disk, so upgrades briefly interrupt the API. The PVC and HelmRelease belong to the same Flux Kustomization, allowing the API pod to trigger `WaitForFirstConsumer` disk binding.

Splunk 0.120.0 has a malformed legacy schema keyword (`deprecated` is a string), rejected by Helm 4. Schema checking is disabled only for that HelmRelease; its rendered configuration is validated with the actual Collector binary.

## Prepare secrets

Prerequisites: Azure CLI, GitHub CLI, Helm **4.0.4**, kubectl, Ruby, Python **3.9+**, ripgrep, SOPS and age. Install Flux **2.10.0** at `.local/bin/flux` (or on PATH).

Use a fork or a GitOps repository you administer. The sample contains no deployment credentials or age recipient: generate your own before bootstrap. All Flux paths are relative to the root of `kedify/examples`, including the `samples/splunk-flux-otel/` prefix. Keep that layout in your fork. The bootstrap command updates the Git source for your chosen owner, repository and branch.

```sh
cp .env.example .env
# Edit .env locally; never commit it or paste tokens into chat.
# Set KEDIFY_ORG_ID, KEDIFY_API_KEY, SPLUNK_HEC_ENDPOINT and SPLUNK_HEC_TOKEN.
# Create the mobility_metrics metrics index and a HEC token for it in your Splunk instance.
python3 scripts/prepare-secrets.py --platform
git add .sops.yaml infrastructure/secrets clusters/mobility-global/reconciliation.yaml
git commit -m 'Configure encrypted deployment credentials'
git push
```

The secrets and Splunk Kustomizations start suspended so independent infrastructure can deploy before credentials are available. This script enables them once all credentials have been encrypted. Commit its reconciliation change along with the generated `.sops.yaml` and secrets. `.env`, `.local/`, private age keys and chart/render caches are ignored by Git.

The script generates a private age key and PostgreSQL password under gitignored `.local/`. Back up the age key privately: it is needed to recover/edit encrypted credentials. Repeated runs reuse the same key/password. The realm is shown under Splunk Observability Cloud **Settings → your username → Organizations**, or in the API/ingest endpoint hostname. Splunk Cloud Platform is a different product; its HEC tokens cannot replace an Observability ingest token.

## Provision and bootstrap

```sh
az login
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
# Defaults: AZURE_LOCATION=westeurope, GITHUB_OWNER=kedify,
# GITHUB_REPOSITORY=examples, GITHUB_BRANCH=main.
# For a personal fork, also set GITHUB_PERSONAL=true.
export GITHUB_OWNER=your-github-owner
export GITHUB_REPOSITORY=examples
export GITHUB_PERSONAL=true
scripts/bootstrap.sh
scripts/status.sh
```

Bootstrap uses `AZURE_SUBSCRIPTION_ID`, creates/reuses resource group and AKS `mobility-global`, and uses only `.local/kubeconfig`. It does not switch the user's normal Kubernetes context. Set `GITHUB_PERSONAL=false` for an organization-owned repository. GitHub bootstrap needs repository administration/deploy-key permissions and a GitHub token available to Flux. Existing resources are inspected before reuse; access errors are not treated as absence.

Flux dependency order is namespaces/sources → encrypted secrets → infrastructure → nginx/Collector → ScaledObject → MetricPredictor. CRDs and controller readiness are gated before custom resources. Do not manually Helm-install duplicate releases.

## Validate before deployment

```sh
scripts/download-charts.sh
ruby scripts/validate.rb
# Linux example; macOS release binaries are also available:
curl -fsSL https://github.com/signalfx/splunk-otel-collector/releases/download/v0.120.0/otelcol_linux_amd64 -o .cache/otelcol
chmod +x .cache/otelcol
SPLUNK_PLATFORM_HEC_TOKEN=validation K8S_NODE_NAME=validation \
 K8S_POD_NAME=validation K8S_NAMESPACE=observability \
 .cache/otelcol validate --config=.cache/rendered/splunk-collector.yaml
```

Rendering checks every component and Kustomization, keeps the configured Splunk metrics exporter, verifies the scaling exporter, and checks that Predictor cannot drive nginx scaling. Chart archive checksums are committed in `charts.lock.json`. The repository workflow [validate-splunk-flux-otel.yaml](../../.github/workflows/validate-splunk-flux-otel.yaml) runs these checks when this sample changes.

## Observe metrics and scaling

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl --context mobility-global -n ingress-system port-forward svc/haproxy-kubernetes-ingress 8080:80
# In another terminal:
curl -H 'Host: nginx.demo.local' http://127.0.0.1:8080/
```

Use a separate local-only port-forward for the scaler:

```sh
kubectl --context mobility-global -n keda port-forward svc/otel-scaler 19090:9090
curl --fail http://127.0.0.1:19090/memstore/names
curl --fail -H 'Content-Type: application/json' --data \
 '{"query":"sum(haproxy_backend_http_requests_total{workload_namespace=demo,workload=nginx})","operationOverTime":"rate"}' \
 http://127.0.0.1:19090/memstore/query
```

Confirm fresh samples, two HAProxy producer identities, and actual backend label `proxy=demo_svc_nginx_http`. `producer_uid` preserves identity across pod replacement. The scaling filter drops all other metrics/backends before adding workload labels. Verify the stored metric name; do not treat HTTP 200 or a zero value alone as proof of healthy ingestion.

Policy: total RPS / 20 RPS per nginx replica; bounds 1–5, 15s polling, 60s rate retention and 60s HPA downscale stabilization. Missing-metric errors are enabled. Stale data and exporter errors must be checked independently. Ports: 4317 OTLP ingestion, 4318 external scaler protocol, 9090 diagnostics.

## Bounded load test through Flux

The load-test Flux Kustomization is opt-in and starts suspended. Set its `spec.suspend: false` in `clusters/mobility-global/reconciliation.yaml`, then commit/push. The Job sends 60 RPS for three minutes, then 120 RPS for three minutes, and exits. Expect about three replicas, a cap of five, then return to one after idle samples and stabilization. Confirm achieved rate and no dropped k6 iterations.

Watch with `kubectl --context mobility-global -n demo get deploy,scaledobject,hpa -w` and read `job/nginx-loadtest-01` logs. Remove the overlay through Git afterward. For another run, change the Job name in Git; do not mutate an existing Job's immutable template. The Job has a 480s deadline and no retries.

## Verify recording and independence

```sh
kubectl --context mobility-global -n demo get mp nginx-recording -o yaml
kubectl --context mobility-global -n keda exec postgres-0 -- \
 psql -U predictor -d predictor -c \
 "SELECT count(*), min(timestamp), max(timestamp) FROM metrics WHERE name='nginx-rps';"
```

Counts and timestamps must advance and recorded RPS must follow load. Verify history survives PostgreSQL/Predictor pod replacement. To prove independence, commit Predictor `replicaCount: 0`, repeat traffic, verify OTel/HPA scaling continues, then revert the commit. The nginx ScaledObject must retain only its named `measured` external OTel trigger.

Confirm fresh HAProxy and cluster metrics in Splunk. The MP contains no synthetic CSV seed; early training may report insufficient data without invalidating successful recording.

## Rollback and cleanup

Revert configuration commits and let Flux reconcile. Do not reset the scaler store or delete the PostgreSQL PVC to diagnose ingestion. Deleting resource group `mobility-global` is a separate, deliberate teardown that destroys the cluster and its persisted data; export any recording history first. No automatic cloud teardown is configured.

## Optional staged bootstrap

`python3 scripts/prepare-secrets.py --kedify-only` encrypts only the Kedify and PostgreSQL credentials and enables their Flux dependency. Splunk stays suspended until backend credentials are supplied. For Cloud Platform, run again with `--platform`; for the optional Observability profile, use a realm/ingest token and no backend flag. Commit all generated Secret/settings files, `.sops.yaml`, and reconciliation changes. A Cloud Platform HEC token is not an Observability ingest token.

The Agent 0.8.3 controller also needs cluster-wide read-only ConfigMap discovery with optional autowiring RBAC disabled; this is granted explicitly through `agent.extraRbacRules`. Self-update and component-install permissions remain disabled.

## Splunk backend

The default profile uses **Splunk Cloud Platform** through HEC. **Observability Cloud** is a separate profile. No realm is needed for Cloud Platform.

- Set your HEC endpoint in `SPLUNK_HEC_ENDPOINT`, for example `https://your-instance.splunkcloud.com:8088/services/collector/event`.
- Create the `mobility_metrics` metrics index, or change `index` and `metricsIndex` in `infrastructure/splunk/release.yaml` and the example SPL together.
- Create a HEC token restricted to that index and set `SPLUNK_HEC_TOKEN`; its value is SOPS-encrypted by the preparation script.
- Both the normal Collector metrics pipelines and `metrics/haproxy` export through `splunk_hec/platform_metrics`; the separate `metrics/scaling` branch still exports OTLP/gRPC to the OTel Scaler.
- Logs and traces are disabled for the metrics-only token. The Collector’s bundled Kubernetes/node metrics collection remains enabled.
- TLS certificate verification is enabled. The original disposable trial required `splunkPlatform.insecureSkipVerify: true` for its self-signed certificate; that exception is not enabled in this reusable sample.

Use `SPLUNK_HEC_ENDPOINT` and `SPLUNK_HEC_TOKEN` in `.env`, then run `scripts/prepare-secrets.py --platform`. To use Observability Cloud instead, replace the release’s `spec.values` with `infrastructure/splunk/observability-values.yaml`, supply a real `SPLUNK_REALM` and ingest-capable `SPLUNK_ACCESS_TOKEN`, and run `scripts/prepare-secrets.py` without `--platform`. Preserve the existing chart/release identity. The Observability profile keeps the same selected metric and scaling branch.

Inspect the token under **Settings → Data Inputs → HTTP Event Collector**, and the index under **Settings → Indexes**. If you submit the optional `mobility_setup_check` metric through HEC, query it with:

```spl
| mstats latest(_value) AS value WHERE index=mobility_metrics AND metric_name=mobility_setup_check
```

For incoming HAProxy counter values:

```spl
| mstats latest(_value) AS requests WHERE index=mobility_metrics AND metric_name=haproxy_backend_http_requests_total BY proxy,pod
```

To create a request-rate report in your instance, use `splunk/reports/nginx-request-rate.spl`; it sums per-producer counter rates in 30-second buckets.

For this small two-node reproduction, HAProxy reserves 100m CPU per pod, OTel Scaler 100m, and Splunk node agents 100m each. The stock reservations left insufficient scheduling space despite low observed usage. These are demo settings, not production sizing recommendations.

## Original deployment verification — 2026-10-29

These historical results describe the original standalone deployment, not a deployment created by cloning this repository. Re-run the checks above for your own cluster.

All six HelmReleases were Ready. HAProxy metrics were fresh in both Splunk and OTel Scaler, and the exact scaling query was verified against real stored data. The named `measured` external trigger was the only trigger on nginx.

The GitOps k6 Job completed **32,401 requests, zero failures, zero dropped iterations**. nginx reached **3 replicas at about 60 RPS**, then **5 replicas at about 120 RPS**, and returned to **1 replica** after traffic stopped. During the 120-RPS phase Predictor was at zero replicas and nginx still reached five, proving that the forecast model does not drive scaling. Predictor was restored to one replica and recording resumed.

PostgreSQL history survived replacement of its pod on the existing Azure Disk PVC. The final check found 21 recorded samples, including values near 120 RPS and idle zeroes. MetricPredictor was Ready with its KEDA source subscribed. See `verification/results.json` for sampled observations. The load-test Kustomization was suspended again after verification.
