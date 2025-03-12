# Sample applications that use KEDA
Source code for examples used in blog posts hosted at [https://www.kedify.io/blog](https://www.kedify.io/blog), used in tutorials hosted at [https://www.kedify.io/tutorials](https://www.kedify.io/tutorials) and other sample applications around KEDA and Kedify.

| Directory                                 | Description                          | Used KEDA scalers                   |
| ----------------------------------------- | ------------------------------------ | ----------------------------------- |
| [envoy-http-scaler](./envoy-http-scaler)  | This example demonstrates how to use the already exisiting envoy to scale a deployment based on the request rate  | Kedify Envoy HTTP |
| [grpc-responder](./grpc-responder)        | This application can be scaled by incoming gRPC traffic, including scale to zero  | Kedify HTTP |
| [http-server](./http-server)              | This application can be scaled by incoming HTTP traffic, including scale to zero  | Kedify HTTP |
| [kafka](./kafka)                          | This application can be scaled by number of messages in the Kafka topic, including scale to zero  | Kafka |
| [minute-metrics](./minute-metrics)        | This application can be scaled by metrics coming from an REST endpoint that changes value every few minutes  | Metrics API |
| [stable-diffusion](./stable-diffusion)    | This application demonstrates scaling AI workloads that runs on GPU-enabled nodes based on a job queue pattern | RabbitMQ Queue |
| [websocket-server](./websocket-server)    | This application can be scaled by incoming Websocket traffic | Kedify HTTP |
| [work-simulator](./work-simulator)        | This application simulates work tasks and can be scaled based on custom Prometheus metrics | Prometheus |


# Externally located sample applications that use KEDA
| Name                              | Description                          | Used KEDA scalers                   |
| -------------------------------------- | ------------------------------------ | ----------------------------------- |
| [dapr-producer-consumer][1]            | This app shows how to use custom metrics coming from Dapr ecosystem to autoscale Dapr microservices (push model) | OTel |
| [opentelemetry-demo][2]                | This app autoscales two backend microservices based on load happening on frontend component (push model) | OTel |
| [podinfo-webapp][3]                    | This demonstrates howto use OTel collector to scrape metrics from a webapp and use them for scaling (pull model) | OTel |

[1]: https://github.com/kedify/otel-add-on/tree/main/examples/dapr
[2]: https://github.com/kedify/otel-add-on/tree/main/examples/metric-push
[3]: https://github.com/kedify/otel-add-on/tree/main/examples/metric-pull
