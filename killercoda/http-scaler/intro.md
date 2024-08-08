# Introduction to HTTP Scaler with Kedify

In this tutorial, we'll explore KEDA (Kubernetes Event-Driven Autoscaling) with Kedify, a tool that simplifies KEDA installation and management. You'll learn to install KEDA with Kedify, scale applications based on HTTP request metrics, and use `Ingress`{{}} autowiring.

Kedify automates KEDA installation and lifecycle management on your Kubernetes cluster, including upgrades. KEDA's HTTP scaler lets you adjust application instances based on incoming HTTP requests, ensuring responsiveness during high traffic and optimizing resources during low traffic.

Kedify's HTTP Scaler is more performant than the KEDA upstream version. For details, see the [Kedify HTTP Scaler blog post](https://kedify.io/resources/blog/http-scaler-launch).

Kedify also simplifies traffic routing with `Ingress`{{}} autowiring, automatically configuring `Ingress` resources to match autoscaling setups. This reduces misconfiguration risks and provides a seamless experience for managing ingress, with a safe fallback and built-in recovery mechanisms.

##### 1 / 4
