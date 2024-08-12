curl_status=$(curl -LI http://keda-meets-gw.com -o /dev/null -w '%{http_code}\n' -s)
if [[ "$curl_status" != "200" ]]; then
    exit 1
fi
