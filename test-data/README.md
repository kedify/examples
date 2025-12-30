# Testing resources for Kedify & KEDA


## Basic: Sample SO and SJ
```bash
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/minutemetrics.yaml
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/target.yaml
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/so.yaml
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/sj.yaml
```

## Cluster/TriggerAuthentications
Creates 8 TAs and 8 CTAs
```bash
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/tas-ctas.yaml
```

## Bulk creation:
Following command creates 5 namespaces (named test-1 - test-5), in each namespace 25 SOs and 20 SJs
```bash
curl -s https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/create_resources.sh | \
bash -s -- 5 25 20 test
```
>Usage: ./create_resources.sh <num_namespaces> <scaled_objects_per_ns> <scaled_jobs_per_ns> [namespace_prefix]


## Pod Resource Profiles (PRP)
Demonstrates KEDA Pod Resource Profile functionality with different trigger types:

### 1. ScaledObject-based PRP
```bash
# Deploy nginx with ScaledObject and activation-based PRP
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/prp-so.yaml
```

This demonstrates PodResourceProfiles triggered by ScaledObject state changes:
- **nginx-active**: 250M memory when ScaledObject is activated by HTTP traffic
- **nginx-standby**: 30M memory when ScaledObject is deactivated (5s delay)
- Uses `kedify-http` trigger for HTTP-based autoscaling

### 2. Container Lifecycle-based PRP
```bash
# Deploy nginx2 with container lifecycle PRP
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/prp.yaml
```

This demonstrates PodResourceProfile triggered by container lifecycle events:
- **nginx2**: Adjusts to 30M memory after container becomes ready (30s delay)
- Uses `containerReady` trigger type for lifecycle-based resource management

## MetricPredictor (Predictive Autoscaling)
Demonstrates KEDA predictive autoscaling using machine learning models to forecast workload patterns:

```bash
# Deploy complete predictive autoscaling stack (deployed in default namespace)
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/metric-predictor.yaml
```

This setup includes:
- **Metrics API Server**: Simulates cyclical traffic patterns with two daily peaks
- **Demo Application**: Nginx-based target for scaling operations  
- **ScaledObject with Predictive Triggers**: Combines live metrics with ML forecasts
- **MetricPredictor**: Prophet-based time series model for 10-minute ahead predictions

## ScalingGroup (Resource Capacity Management)
Demonstrates KEDA ScalingGroup functionality for managing shared resource capacity across multiple ScaledObjects:

```bash
# Deploy scaling group demonstration with capacity limits
kubectl apply -f https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/scaling-group.yaml
```

This setup includes:
- **Two Application Deployments**: `app-1` and `app-2` (initially scaled to 0)
- **Metric Source Deployments**: `test-keda-metric-1` and `test-keda-metric-2` to trigger scaling
- **ScaledObjects with Group Labels**: Both tagged with `scaling-group: cap-5`
- **ScalingGroup Resource**: Named `max-group` with capacity limit of 5 replicas


## Simulating a k8s cluster that has also some other workloads:
```
# create a cluster w/ 7 worker nodes
k3d cluster delete ; k3d cluster create --servers 7 --no-lb --k3s-arg "--disable=traefik,servicelb,local-storage@server:*"
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# install kedify
kubectl kedify i --email foo@bar -y

# 30 pods in total
curl -s https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/create_resources.sh | \
OTHER_DEPLOYMENTS=1 \
bash -s -- 2 10 4 scale

# create 10 namespaces (t-1 - t-10) and in each 6 deployments and 1 stateful set (with pause container)
# 70 pods in total
curl -s https://raw.githubusercontent.com/kedify/examples/main/test-data/resources/create_resources.sh | \
OTHER_DEPLOYMENTS=6 \
OTHER_STATEFUL_SETS=1 \
bash -s -- 10 0 0 t
```
