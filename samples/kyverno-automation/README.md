## KEDA + Kyverno Demo

The repo contains two Kyverno `ClusterPolicy` that contain generate rule for creating a KEDA `ScaledObject` when `Deployment` resource is created.
This can be restricted either on the namespace level (using explicit allowlist, or label selector) and/or on the deployment level using labels or annotations.

`create-so-policy.yaml` contains an opinionated definition of `ScaledObject` with all the knobs already tunned and `create-so-policy-templating.yaml` contains
a more dynamic form, where the values for the ScaledObject are read from a `ConfigMap`.

## Steps

Prepare Kubernetes cluster

```
k3d cluster delete && k3d cluster create --no-lb --k3s-arg "--disable=traefik,servicelb@server:*"
```

Install Kyverno

```
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update kyverno
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
```

Install KEDA

```
helm upgrade -i keda kedify/keda --namespace keda --create-namespace --version v2.17.1-0
```

Kyverno needs to crud the ScaledObjects

```
k apply -f rbac.yaml
```

First cpol

```
k apply -f create-so-policy.yaml
```

Second cpol

```
k apply -f create-so-policy-templating.yaml
```

Now trigger the cpols by creating the Deployments

```
k apply -f depls.yaml
```

Verify that `ScaledObject` were also created

```
k get so -A
```
