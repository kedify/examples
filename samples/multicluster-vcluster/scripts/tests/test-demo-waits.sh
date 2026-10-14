#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../vcluster-common.sh"
source "$(dirname "$0")/../scaling-common.sh"

# No cluster access. Advance Bash's timer instead of sleeping.
sleep() { SECONDS=$((SECONDS + 1)); }
DEMO_WAIT_TIMEOUT_SECONDS=1
vcluster_kubectl() { return 1; }
if wait_for_deployment_replicas 3 0 >/dev/null 2>&1; then
  echo 'FAIL: an API failure was accepted as zero replicas' >&2
  exit 1
fi

fixture="$(mktemp)"
trap 'rm -f "${fixture}"' EXIT
DEMO_WAIT_TIMEOUT_SECONDS=3
vcluster_kubectl() {
  local response
  IFS= read -r response <&8 || return 1
  printf '%s' "${response}"
}
printf '0:1\n0:\n' >"${fixture}"
exec 8<"${fixture}"
wait_for_deployment_replicas 3 0 >/dev/null
if IFS= read -r _ <&8; then
  echo 'FAIL: zero was accepted while an old Pod remained ready' >&2
  exit 1
fi
exec 8<&-

printf '3:2\n3:3\n' >"${fixture}"
exec 8<"${fixture}"
wait_for_deployment_replicas 1 3 >/dev/null
if IFS= read -r _ <&8; then
  echo 'FAIL: scale-up was accepted before ready replicas matched' >&2
  exit 1
fi
exec 8<&-
echo 'PASS: failed reads remain unknown; zero and scale-up wait for ready replicas'
