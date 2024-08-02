This last step is intended for advanced and detailed understanding of the internals how KEDA works. This is purely optional and contains low level details, you won't need to know any of this for your application autoscaling but if you are interested to learn more and not affraid to dive into the KEDA's plumbing, you are welcome to continue.

> None of the following information is required to understand KEDA and/or configure application autoscaling.

TODO elaborate this whole page:
get query parameters from HPA
```bash
metric_name=$(kubectl get -ndefault hpa keda-hpa-demo -o json | jq --raw-output '.spec.metrics[0].external.metric.name')
label_selector=$(kubectl get -ndefault hpa keda-hpa-demo -o json | jq --raw-output '.spec.metrics[0].external.metric.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
encoded_label=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$label_selector'''))")
```{{exec}}

get metric value
```bash
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/default/$metric_name?labelSelector=$encoded_label" | jq '.'
```{{exec}}

Now not only you can autoscale using KEDA, but you also have better understanding of how this all works! Check out our other courses at:
https://killercoda.com/kedify/course/killercoda

##### bonus / 4
