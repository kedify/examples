IP=$(kubectl get ingress -ndefault blue -o json | jq --raw-output '.status.loadBalancer.ingress[].ip')
curl_status=$(curl -LI -H "host: blue.com" http://$IP -o /dev/null -w '%{http_code}\n' -s)
if [[ "$curl_status" != "200" ]]; then
    exit 1
fi
