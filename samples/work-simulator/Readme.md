# Work Simulator

This is a simple work simulator application in Go, deployable in Kubernetes. The application accepts HTTP requests on the `/work` endpoint, simulates processing tasks with configurable delays, and exposes Prometheus metrics for monitoring and autoscaling.

---

## Content

- [Step-by-Step KEDA Guide](./guide.md): A comprehensive guide on how to deploy and scale the `work-simulator` application using KEDA and Prometheus.
- [Application Details](./app.md): Detailed explanation of the `work-simulator` application, including its features, build instructions, and deployment.
- [Migration Path from Prometheus to OTel](./prom2otel.md): Step-by-step explanation of how to take the previous setup and turn it into OTel collector + OTel scaler setup.
