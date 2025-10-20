# Prefill Decode Disaggregation Autoscaling
This example explores how to deploy llm-d PD Disaggregation and how to scale it on GKE.

# Understanding PD Disaggregation 
PD Disaggregation consists of separating prefill and decode stages to different instances. This adds extra complexity to serving models since we need to share KV cache between instances. On the other hand, benefits include we can scale each stage separately.

See [this page](https://github.com/llm-d/llm-d-inference-scheduler/blob/main/docs/dp.md) to understan how PD disaggregation inference works.

# Gateway API
Intall Gateway API Inference Extension from gaie.md
Ensure you have all resources available

# Running PD disaggregation from llm-d-modelservice(smaller model)
In this example we run `facebook/opt-125m` model over two L4 accelerators on `g2-standard-8` nodes. 

Ensure you have a cluster with available accelerators. Yo can see the `vllm-autoscaling` example from this repo to setup a cluster and accelerator tooling.

At this point you should have a `gateway` waiting for `inferencepool` and `httproute` to be created.


[llm-d-modelservice](https://github.com/llm-d-incubation/llm-d-modelservice/tree/main/examples) is a helm chart from the llm-d comunity that contains multiple example deployments.

This will create various resources including
- prefill/decode instances
- inferencepool.inference.networking.x-k8s.io
- httproute

The original example asumes we have a `llm-d-infra` instalation. We dont need to deploy the full scale of the example, and for demo purposes we adjust deployments to run smaller models and less nodes.

```
helm repo add llm-d-modelservice https://llm-d-incubation.github.io/llm-d-modelservice/
helm template pd llm-d-modelservice/llm-d-modelservice -f values-pd.yaml 
helm upgrade -i pd llm-d-modelservice/llm-d-modelservice -f values-pd.yaml 
```

# Autoscaling

Deploy the autoscaling components using `./setup.sh` including installation of:

- KEDA
- KEDA OTel Scaler & OTel Operator
- ScaledObject

Ensure you have cert-manger in cluster before instaling the KEDAOTEL operator so we can use the `sidecar`s.

After the components are in place, you can run `./loadgeneration.sh`

It will get the Gateway API IP and send similar requests to it. 
As a result you should see the decode deployment being scheduled. This is because the prompt is the same every time and prefill is skiped.

Now prefil and decode scales based on diferent scalers. 

# Sumary 

To confirm PD is succesfully working, send completion requests and you should be able to get responses for differentt size of prompts.

You can also check metrics on the keda scaler and you should see diferent values to the amount of request arriving at the prefill or decode instances.

If you want to inspect logs to confirm the behaviour

- check EPP logs and you should see prefill and decode selection
- check the decode proxy and you should see scenarios where it completely ignores prefill or logs when connecting to prefill instance
- check decode main container logs and you should see completeion request with the do_remote_decode=false
- check prefill logs and you should see the completions request of new prompts.
- on prefil and decode you should se logs refering to nixlconnector working to share the KV values

# Vanila PD Disagrgation

If you are curious for vanila PD disagregation on vLLM you can check the vllm [example](https://github.com/vllm-project/vllm/blob/main/examples/online_serving/disaggregated_prefill.sh)

# Check metrics are present on the keda scaler

```
(kubectl port-forward svc/keda-otel-scaler 9090&)
curl -X 'GET' \
  'http://localhost:9090/memstore/data' \
  -H 'accept: application/json'

curl -X 'POST' \
  'http://localhost:9090/memstore/query' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "operationOverTime": "count",
  "query": "vllm:request_success_total{deployment=pd-llm-d-modelservice-decode}"
}'

```