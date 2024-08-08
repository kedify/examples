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
  hey -z 5s -c 10 -q 1 http://blue.com > /dev/null
  
  echo "~20 req/sec" >> /tmp/hey.output
  hey -z 5s -c 20 -q 1 http://blue.com > /dev/null
  
  echo "~30 req/sec" >> /tmp/hey.output
  hey -z 5s -c 30 -q 1 http://blue.com > /dev/null

  echo "~40 req/sec" >> /tmp/hey.output
  hey -z 5s -c 40 -q 1 http://blue.com > /dev/null

  echo "~50 req/sec" >> /tmp/hey.output
  hey -z 5s -c 50 -q 1 http://blue.com > /dev/null
  
  echo "~60 req/sec" >> /tmp/hey.output
  hey -z 5s -c 60 -q 1 http://blue.com > /dev/null

  echo "~70 req/sec" >> /tmp/hey.output
  hey -z 5s -c 70 -q 1 http://blue.com > /dev/null
  
  echo "~80 req/sec" >> /tmp/hey.output
  hey -z 5s -c 80 -q 1 http://blue.com > /dev/null
  
  echo "~90 req/sec" >> /tmp/hey.output
  hey -z 5s -c 90 -q 1 http://blue.com > /dev/null
  
  echo "~100 req/sec" >> /tmp/hey.output
  hey -z 5s -c 100 -q 1 http://blue.com > /dev/null
  
  echo "~90 req/sec" >> /tmp/hey.output
  hey -z 5s -c 90 -q 1 http://blue.com > /dev/null
 
  echo "~70 req/sec" >> /tmp/hey.output
  hey -z 5s -c 70 -q 1 http://blue.com > /dev/null
  
  echo "~40 req/sec" >> /tmp/hey.output
  hey -z 5s -c 40 -q 1 http://blue.com > /dev/null

  echo "~5 req/sec" >> /tmp/hey.output
  hey -z 10s -c 5 -q 1 http://blue.com > /dev/null

  echo "benchmark finished, press ctrl+c to finish the watch loop" >> /tmp/hey.output
)&
watch --no-title -n1 --color -x bash -c "f"
