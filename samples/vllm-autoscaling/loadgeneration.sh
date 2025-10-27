#!/bin/bash
(kubectl port-forward svc/vllm-router-service 30080:80 &> /dev/null)& pf_pid=$!
(sleep $((1*60)) && kill ${pf_pid})&

end=$((SECONDS+60))
i=0
while [ $SECONDS -lt $end ]; do
  i=$((i+1))
  echo "----- $(date -Is) [#$i] -----"
  curl -s -X POST http://localhost:30080/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"facebook/opt-125m","prompt":"how the future looks like if everyone is good","max_tokens":100}' \
  | jq .
  sleep 0.3   # tweak or remove to go faster
done
