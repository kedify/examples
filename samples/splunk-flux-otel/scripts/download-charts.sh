#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache/charts
curl -fsSL https://github.com/haproxytech/helm-charts/releases/download/kubernetes-ingress-1.47.3/kubernetes-ingress-1.47.3.tgz -o .cache/charts/haproxy.tgz
curl -fsSL https://github.com/signalfx/splunk-otel-collector-chart/releases/download/splunk-otel-collector-0.120.0/splunk-otel-collector-0.120.0.tgz -o .cache/charts/splunk.tgz
curl -fsSL https://kedify.github.io/charts/keda-v2.20.0-1.tgz -o .cache/charts/keda.tgz
curl -fsSL https://kedify.github.io/charts/kedify-agent-v0.8.3.tgz -o .cache/charts/agent.tgz
helm pull oci://ghcr.io/kedify/charts/otel-add-on --version 0.1.5 --destination .cache/charts
helm pull oci://ghcr.io/kedify/charts/kedify-predictor --version 0.1.9 --destination .cache/charts
python3 - <<'PY'
import hashlib,json,pathlib
for name,digest in json.load(open('charts.lock.json')).items():
    assert hashlib.sha256(pathlib.Path('.cache/charts',name).read_bytes()).hexdigest()==digest, 'Chart checksum changed: '+name
print('Pinned chart checksums verified')
PY
