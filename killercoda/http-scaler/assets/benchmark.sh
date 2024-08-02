#!/usr/bin/env bash

set -euo pipefail

function f() {
    echo "Metrics from KEDA:"
    kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq -C '.'
    echo ""
    echo "Running pods:"
    kubecolor --force-colors get po -ndefault
    cat /tmp/hey.output
}
export -f f

trap "kill $(pidof hey) 2>/dev/null; kill -SIGKILL $(pidof watch) 2>/dev/null" EXIT
(
  echo "" > /tmp/hey.output
  echo "" >> /tmp/hey.output
  echo "warming up the application" >> /tmp/hey.output
  curl --connect-timeout 60 --max-time 60 http://blue.com > /dev/null 2>&1

  echo "" > /tmp/hey.output
  echo "" >> /tmp/hey.output
  echo "running hey benchmark" >> /tmp/hey.output
  echo "~10 req/sec" >> /tmp/hey.output
  hey -z 5s -c 10 -q 2 http://blue.com > /dev/null
  
  echo "~15 req/sec" >> /tmp/hey.output
  hey -z 5s -c 15 -q 2 http://blue.com > /dev/null
  
  echo "~25 req/sec" >> /tmp/hey.output
  hey -z 5s -c 25 -q 2 http://blue.com > /dev/null

  echo "~35 req/sec" >> /tmp/hey.output
  hey -z 5s -c 35 -q 2 http://blue.com > /dev/null

  echo "~50 req/sec" >> /tmp/hey.output
  hey -z 5s -c 50 -q 2 http://blue.com > /dev/null

  echo "benchmark finished, you can observe scale down now ..." >> /tmp/hey.output
)&
watch --no-title -n1 --color -x bash -c "f"
