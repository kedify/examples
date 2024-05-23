#!/bin/bash

for i in {1..20}; do
    # echo "Current number of replicas: $(kubectl get pods --no-headers | wc -l)"
    echo "GET http://34.93.135.62:1323/" | vegeta attack -rate=100 -duration=1s | vegeta report
    echo "Attack for completed, iteration $i/20."
    
    sleep 10s
done

echo "Load test completed."

