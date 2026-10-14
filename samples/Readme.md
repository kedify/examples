# Sample applications that use KEDA and Kedify

Source code for [blog examples](https://www.kedify.io/blog),
[tutorials](https://www.kedify.io/tutorials), and other KEDA and Kedify samples.
Each directory below contains its own setup instructions or example manifests.

| Directory | Description | Scalers / features |
| --- | --- | --- |
| [agones-fleet-scale-adapter](./agones-fleet-scale-adapter) | Scale an Agones game server Fleet through ScaleAdapter, including scale to zero | Kubernetes Resource, ScaleAdapter |
| [argo-rollouts-canary](./argo-rollouts-canary) | Autoscale canary deployments with weighted traffic splitting through the Argo Rollouts traffic-router plugin | Kedify HTTP, Argo Rollouts |
| [azul-prp](./azul-prp) | Vertically scale a Java application running on Azul JVM | PodResourceProfile |
| [chain-scaling](./chain-scaling) | Scale a frontend and chained backends using HTTP demand and workload dependencies | Kedify HTTP, Kubernetes Workload |
| [envoy-http-scaler](./envoy-http-scaler) | Autoscale from request rate using an existing Envoy proxy | Kedify Envoy HTTP |
| [grpc-responder](./grpc-responder) | Scale a gRPC responder from incoming traffic, including scale to zero | Kedify HTTP |
| [http-add-on_with_istio](./http-add-on_with_istio) | Autoscale HTTP applications with Istio service mesh and gateway | Kedify HTTP, Istio |
| [http-scaler-healthchecks-with-paths](./http-scaler-healthchecks-with-paths) | Route load-balancer health probes using a host embedded in the request path | Kedify HTTP |
| [http-scaler-multiple-triggers](./http-scaler-multiple-triggers) | Route and scale applications using multiple HTTP triggers, headers, and path prefixes | Kedify HTTP |
| [http-scaler-with-gloo](./http-scaler-with-gloo) | Autoscale HTTP applications with Gloo Gateway and traffic autowiring | Kedify HTTP, Gloo |
| [http-scaler-with-header-routing](./http-scaler-with-header-routing) | Route and scale traffic using exact, wildcard, or regular-expression HTTP headers | Kedify HTTP |
| [http-server](./http-server) | Scale an HTTP server from incoming traffic, including scale to zero | Kedify HTTP |
| [kafka](./kafka) | Scale a Kafka consumer from topic backlog, including scale to zero | Kafka |
| [kyverno-automation](./kyverno-automation) | Automatically create ScaledObjects when Deployments are created | Kyverno |
| [llmd-pd-disaggregation-autoscaling](./llmd-pd-disaggregation-autoscaling) | Deploy llm-d on GKE and independently scale prefill and decode instances | OTel via External scaler |
| [load-generator](./load-generator) | Generate controllable CPU and memory load through REST profiles for autoscaling tests | Helper workload |
| [minute-metrics](./minute-metrics) | Scale from a REST metric that changes every few minutes | Metrics API |
| [multicluster](./multicluster) | Scale workloads across k3d member clusters from a central KEDA installation | Kubernetes Resource, multi-cluster scaling |
| [multicluster-vcluster](./multicluster-vcluster) | Run central Agent/KEDA/KPA on AKS and independently scale discovered vCluster tenants, with live onboarding and terminal views | CPU, Redis, ScaledJob, KPA, vCluster discovery |
| [otel-ingress-nginx-poc](./otel-ingress-nginx-poc) | Scale a frontend and Apollo Router backend from ingress-nginx metrics and workload dependencies | OTel, Kubernetes Workload |
| [otel-scaler-pipelines](./otel-scaler-pipelines) | Route selected metrics through an OTel collector with TLS, using pull and push pipelines | OTel |
| [otel-scaler-vertical](./otel-scaler-vertical) | Adjust Pod resources with PodResourceProfile from metrics routed through an OTel collector | OTel, PodResourceProfile |
| [otel-scaler-with-predictor](./otel-scaler-with-predictor) | Combine measured OTel metrics with predictions for autoscaling | OTel, Predictor |
| [scaling-group](./scaling-group) | Enforce a shared scaling capacity across a group of ScaledObjects | ScalingGroup, Kubernetes Workload |
| [stable-diffusion](./stable-diffusion) | Scale image-generation workers from a job queue, with GPU support and shared image storage | RabbitMQ Queue, ScaledObject / ScaledJob |
| [vllm-autoscaling](./vllm-autoscaling) | Deploy vLLM production-stack on GKE and scale from inference metrics | OTel via External scaler |
| [websocket-server](./websocket-server) | Scale a WebSocket server from incoming traffic | Kedify HTTP |
| [work-simulator](./work-simulator) | Simulate work with custom Prometheus metrics and an OTel migration guide | Prometheus, OTel |


## Externally located sample applications that use KEDA

| Name                              | Description                          | Used KEDA scalers                   |
| -------------------------------------- | ------------------------------------ | ----------------------------------- |
| [dapr-producer-consumer][1]            | This app shows how to use custom metrics coming from Dapr ecosystem to autoscale Dapr microservices (push model) | OTel |
| [opentelemetry-demo][2]                | This app autoscales two backend microservices based on load happening on frontend component (push model) | OTel |
| [podinfo-webapp][3]                    | This demonstrates howto use OTel collector to scrape metrics from a webapp and use them for scaling (pull model) | OTel |
| [vllm][4]                              | Three examples that use metrics exposed from accelerator (GPU) to scale LLM models deployed via vLLM: DCGM metrics, sidecar pattern & scraping metrics from router | OTel |
| [cloudwatch-metric-stream][5]          | This example scales an nginx Deployment from an AWS Network Load Balancer's `NewFlowCount` metric. CloudWatch serializes the metric as OpenTelemetry 1.0 and sends it via OTLP to the KEDA OTel scaler. | OTel |

[1]: https://github.com/kedify/otel-add-on/tree/main/examples/dapr
[2]: https://github.com/kedify/otel-add-on/tree/main/examples/metric-push
[3]: https://github.com/kedify/otel-add-on/tree/main/examples/metric-pull
[4]: https://github.com/kedify/otel-add-on/tree/main/examples/vllm
[5]: https://github.com/kedify/otel-add-on/tree/main/examples/cloudwatch-metric-stream
