# Kedify HTTP Scaler with gRPC

This tutorial will guide you through setting up Kedify HTTP Scaler with a gRPC service. Check out [our other tutorial](https://kedify.io/tutorials/http-scaler) to learn more about Kedify fundamentals.

Kedify's HTTP Scaler is not only more performant than the KEDA upstream version (see the [this blog post](https://kedify.io/resources/blog/http-scaler-launch) for more details) but also more feature complete with a convenient gRPC and TLS support.

And as a small bonus, Kedify also simplifies traffic routing with `Ingress`{{}} autowiring, automatically configuring `Ingress`{{}} resources to match autoscaling setups. This reduces misconfiguration risks and provides a seamless experience for managing ingress, with a safe fallback and built-in recovery mechanisms.

&nbsp;
&nbsp;

##### 1 / 4
