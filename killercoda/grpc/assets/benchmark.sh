#!/usr/bin/env bash

set -euo pipefail

function f() {
    echo "Metrics from KEDA:"
    kubectl get --raw '/api/v1/namespaces/keda/services/keda-add-ons-http-interceptor-admin:9090/proxy/queue' | jq -C '.'
    echo ""
    echo "Running pods:"
    kubecolor --force-colors get po -ndefault
    cat /tmp/ghz.output
}
export -f f

trap "kill $(pidof ghz) 2>/dev/null; kill -SIGKILL $(pidof watch) 2>/dev/null" EXIT
(
  echo "" > /tmp/ghz.output
  echo "" >> /tmp/ghz.output
  echo "warming up the application" >> /tmp/ghz.output
  grpcurl -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 responder.HelloService/SayHello > /dev/null 2>&1

  echo "" > /tmp/ghz.output
  echo "" >> /tmp/ghz.output
  echo "running ghz benchmark" >> /tmp/ghz.output
  echo "~10 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 10 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~20 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 20 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~30 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 30 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1

  echo "~40 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 40 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1

  echo "~50 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 50 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~60 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 60 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1

  echo "~70 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 70 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~80 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 80 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~90 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 90 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~100 req/sec" >> /tmp/ghz.output
  ghz -z 5s --rps 100 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~30 req/sec" >> /tmp/ghz.output
  ghz -z 10s --rps 30 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
 
  echo "~15 req/sec" >> /tmp/ghz.output
  ghz -z 10s --rps 15 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1
  
  echo "~10 req/sec" >> /tmp/ghz.output
  ghz -z 15s --rps 10 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1

  echo "~5 req/sec" >> /tmp/ghz.output
  ghz -z 30s --rps 5 --call responder.HelloService/SayHello -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 > /dev/null 2>&1

  echo "" >> /tmp/ghz.output
  echo "benchmark finished, press 'ctrl+c' to kill the watch loop" >> /tmp/ghz.output
  echo "when you are done observing the application scale-in" >> /tmp/ghz.output
)&
watch --no-title -n1 --color -x bash -c "f"
