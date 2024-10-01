# Sample applications that uses KEDA
Source code for examples used in blog posts hosted at [https://www.kedify.io/blog](https://www.kedify.io/blog), used in tutorials hosted at [https://www.kedify.io/tutorials](https://www.kedify.io/tutorials) and other sample applications around KEDA and Kedify.

| Directory                              | Description                          | Used KEDA scalers                   |
| -------------------------------------- | ------------------------------------ | ----------------------------------- |
| [grpc-responder](./grpc-responder)     | This application can be scaled by incoming gRPC traffic, including scale to zero  | Kedify HTTP |
| [minute-metrics](./minute-metrics)     | This application can be scaled by metrics coming from an REST endpoint that changes value every few minutes  | Metrics API |
| [stable-diffusion](./stable-diffusion) | This application demonstrates scaling AI workloads that runs on GPU-enabled nodes based on a job queue pattern | RabbitMQ Queue |
| [websocket-server](./websocket-server) | This application can be scaled by incoming Websocket traffic | Kedify HTTP |
