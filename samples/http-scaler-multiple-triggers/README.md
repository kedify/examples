# HTTP Server - Multi-Trigger Kedify Example

This extended example builds on the basic [HTTP Server](../http-server/README.md) app and demonstrates **multi-trigger HTTP autoscaling** with [Kedify](https://www.kedify.io).

It shows how to configure multiple `kedify-http` triggers on different `ScaledObject`s based on **HTTP headers** or **path prefixes**, enabling fine-grained traffic routing and autoscaling.

---

## 🔧 Features and Routing Strategy

This setup deploys 3 services:

| Name          | Routes Based On     | Example Trigger               |
| ------------- | ------------------- | ----------------------------- |
| `http-server` | traffic (no header) | `host: demo.keda`             |
| `foo`         | `header: app=foo`   | `host: demo.keda`, `app: foo` |
| `bar`         | `header: app=bar`   | `host: demo.keda`, `app: bar` |

Each app is independently autoscaled by its `ScaledObject` using `kedify-http` triggers.

---

## 🚀 Getting Started

### 1. Create k3d Cluster (or use your own)

```bash
k3d cluster create --port "9080:80@loadbalancer"
```

### 2. Deploy Application and Infrastructure

```bash
kubectl apply -f ./manifests.yaml
```

This includes:

* Deployments + Services for `http-server`, `foo`, and `bar`
* A shared Ingress pointing to `demo.keda`

### 3. Deploy Multi-Trigger ScaledObjects

Choose one of the following setups based on your routing strategy:

#### ➤ Path Prefix-based Triggers:

```bash
kubectl apply -f ./so-paths.yaml
```

#### ➤ Header-based Triggers:

```bash
kubectl apply -f ./so-headers.yaml
```

#### ➤ Combined Headers and Path Prefixes:

```bash
kubectl apply -f ./so-paths-headers.yaml
```

## 🌐 Test Traffic Routing

### Fallback route (http-server):

```bash
curl -H "host: demo.keda" http://localhost:9080/
```

### Route to `/info` endpoint:

```bash
curl -H "host: demo.keda" http://localhost:9080/info
```

### Route to `/echo` endpoint:

```bash
curl -H "host: demo.keda" http://localhost:9080/echo
```

### Route to `foo` via header:

```bash
curl -H "host: demo.keda" -H "app: foo" http://localhost:9080/
```

### Route to `bar` via header:

```bash
curl -H "host: demo.keda" -H "app: bar" http://localhost:9080/
```

### Inspect request info:

```bash
curl -H "host: demo.keda" -H "app: foo" http://localhost:9080/echo
```

---

## 📈 Validate Autoscaling

Use `kubectl` to observe scaling behavior:

```bash
kubectl get hpa
kubectl get pods -w
```

---
