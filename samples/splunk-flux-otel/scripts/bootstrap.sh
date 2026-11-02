#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.local/bin:$PATH"
SUBSCRIPTION="${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID to your Azure subscription ID}"
REGION="${AZURE_LOCATION:-westeurope}"
CONTEXT=mobility-global
GITHUB_OWNER="${GITHUB_OWNER:-kedify}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-examples}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
for tool in az flux kubectl python3 gh rg age-keygen; do command -v "$tool" >/dev/null; done
[[ -s infrastructure/secrets/splunk.enc.yaml ]] || echo "Credentials pending: Flux will stage infrastructure while secrets-dependent releases wait."
git diff --quiet && git diff --cached --quiet || { echo 'Commit and push changes before bootstrapping.' >&2; exit 1; }
az account get-access-token --subscription "$SUBSCRIPTION" --query expiresOn -o tsv >/dev/null
mkdir -p .local
chmod 700 .local
if [[ ! -s .local/sops.agekey ]]; then age-keygen -o .local/sops.agekey; fi
chmod 600 .local/sops.agekey
# Distinguish absence from authorization/network failures.
if [[ $(az group exists --subscription "$SUBSCRIPTION" -n mobility-global -o tsv) == false ]]; then
  az group create --subscription "$SUBSCRIPTION" -n mobility-global -l "$REGION" --tags purpose=mobility-global-poc >/dev/null
fi
clusters=$(az aks list --subscription "$SUBSCRIPTION" -g mobility-global --query '[].name' -o tsv)
if ! echo "$clusters" | rg -qx mobility-global; then
  AKS_VERSION=$(az aks get-versions --subscription "$SUBSCRIPTION" -l "$REGION" -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); vs=[p for v in d["values"] if v["version"]=="1.35" and not v.get("isPreview",False) for p in v["patchVersions"]]; print(max(vs,key=lambda x:tuple(map(int,x.split(".")))))')
  printf '%s\n' "$AKS_VERSION" > .local/aks-version
  az aks create --subscription "$SUBSCRIPTION" -g mobility-global -n mobility-global -l "$REGION" --kubernetes-version "$AKS_VERSION" --node-count 2 --node-vm-size Standard_D2s_v5 --tier free --enable-managed-identity --network-plugin azure --network-plugin-mode overlay --no-ssh-key
fi
az aks wait --subscription "$SUBSCRIPTION" -g mobility-global -n mobility-global --created --interval 30 --timeout 1800
az aks get-credentials --subscription "$SUBSCRIPTION" -g mobility-global -n mobility-global --file "$PWD/.local/kubeconfig" --context "$CONTEXT" --overwrite-existing
chmod 600 .local/kubeconfig
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl --context "$CONTEXT" wait --for=condition=Ready nodes --all --timeout=10m
kubectl --context "$CONTEXT" get nodes
flux check --pre --context "$CONTEXT"
# Install the initial trust material before the Git source starts reconciling.
kubectl --context "$CONTEXT" create namespace flux-system --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" -n flux-system create secret generic sops-age --from-file=age.agekey=.local/sops.agekey --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -
FLUX_VERSION=$(flux version --client -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["flux"])')
bootstrap_args=(--owner="$GITHUB_OWNER" --repository="$GITHUB_REPOSITORY" --branch="$GITHUB_BRANCH" --path=samples/splunk-flux-otel/clusters/mobility-global)
if [[ ${GITHUB_PERSONAL:-false} == true ]]; then bootstrap_args+=(--personal); fi
flux bootstrap github "${bootstrap_args[@]}" --context "$CONTEXT" --version "$FLUX_VERSION"
echo 'Flux bootstrapped. Run scripts/status.sh to inspect reconciliation.'
