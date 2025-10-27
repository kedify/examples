#!/bin/bash
GATEWAY_IP=$(kubectl get gateway inference-gateway -n default -o jsonpath='{.status.addresses[0].value}')

end=$((SECONDS+60))
i=0
while [ $SECONDS -lt $end ]; do
  i=$((i+1))
  echo "----- $(date -Is) [#$i] -----"
  curl -s -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"facebook/opt-125m","prompt":"how the future looks like if everyone is good","max_tokens":100}' \
  | jq .
  sleep 0.3   # tweak or remove to go faster
done
