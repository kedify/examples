# vLLM autoscaling with KEDA

This example shows how to deploy the vLLM production-stack on GKE.
This demo shows how to scale vLLM instances using KEDA + Keda Otel Scaler.

# Create a cluster with managed drivers from GKE

We create a COS nodes cluster with L4 accelerators. Use the managed drivers from GKE set up to lastes version(only available on COS nodes only) 
We use the NVIDA operator to handle installation of container toolkit + other resources to allow us to deploy accelerator workloads.

```
gcloud beta container --project "kedify-test" clusters create "kedify-vllm-production-stack-md" --zone "us-central1-b" --no-enable-basic-auth --cluster-version "1.33.4-gke.1172000" --release-channel "regular" --machine-type "g2-standard-8" --accelerator "type=nvidia-l4,count=1,gpu-driver-version=latest" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "200" --metadata disable-legacy-endpoints=true --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/kedify-test/global/networks/default" --subnetwork "projects/kedify-test/regions/us-central1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "0" --max-nodes "2" --location-policy "BALANCED" --enable-ip-access --security-posture=standard --workload-vulnerability-scanning=disabled --no-enable-google-cloud-access --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 1 --binauthz-evaluation-mode=DISABLED --no-enable-managed-prometheus --enable-shielded-nodes --shielded-integrity-monitoring --no-shielded-secure-boot --node-locations "us-central1-b" --gateway-api=standard

gcloud container clusters get-credentials kedify-vllm-production-stack-md --zone us-central1-b --project kedify-test

```

# Install the GPU operator
[NVIDIA GKE GPUs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/google-gke.html)
[GCP GKE installation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpu-operator)
[NVIDIA GPU operator getting started](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html)

For installing dirvers you have many options, as of today GKE ofers to manage the drivers for the 1.30+ GKE clusters.
if yo want to install drivers on your own yo need to specify that on the CLI cluster creation by using the flags: --node-labels="gke-no-default-nvidia-gpu-device-plugin=true" and --accelerator type=...,gpu-driver-version=disabled CLI arguments to disable the GKE GPU device plugin daemon set and automatic driver installation on GPU nodes.

The nvidia operator also suports to have the driver installed by a diferent method if you specify the flag `driver.enabled=false` during helm chart installation.

The following steps are to install the NVIDIA operator to manage some aditional components required.

```
kubectl create ns gpu-operator
#enfoce pod security admision to privileged if any
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged
#check if node feature discovery is disabled, if response is true then disabel it on the operator installation
kubectl get nodes -o json | jq '.items[].metadata.labels | keys | any(startswith("feature.node.kubernetes.io"))'

kubectl apply -n gpu-operator -f - << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-operator-quota
spec:
  hard:
    pods: 100
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values:
        - system-node-critical
        - system-cluster-critical
EOF
```

## Intall the helm chart and no drivers

```
helm install --wait --generate-name \
  -n gpu-operator --create-namespace \
  nvidia/gpu-operator \
  --version=v25.3.4 \
  --set hostPaths.driverInstallDir=/home/kubernetes/bin/nvidia \
  --set toolkit.installDir=/home/kubernetes/bin/nvidia \
  --set cdi.enabled=true \
  --set cdi.default=true \
  --set driver.enabled=false
  ```

A sign of successfull installation is all pods running on the `gpu-operator` namespace

## Test installation

Can run a validation test to see if GPU pods can be scheduled

```
kubectl apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-smoke
spec:
  containers:
  - name: cuda
    image: nvidia/cuda:12.2.2-runtime-ubuntu22.04
    command: ["bash","-lc","nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    cloud.google.com/gke-accelerator: "nvidia-l4"
EOF
```

Logs should show `nvidia-smi` output containing the driver versions installed and the CUDA versions installed.

```
kubectl logs gpu-smoke
kubectl delete po gpu-smoke
```

# Install vLLM production-stack chart

[production-stack](https://docs.vllm.ai/en/v0.9.2/deployment/integrations/production-stack.html#deployment-using-vllm-production-stack)

Once the GPU nodes are up and running we can deploy a small model after downloading a reference values file [values-01-minimal-example.yaml](https://github.com/vllm-project/production-stack/blob/main/tutorials/assets/values-01-minimal-example.yaml)

We used a update file version called `vllm-prod-stack-values.yaml` to use the `nvidia` RuntimeClass porvided by the NVIDIA operator to avoid getting the error:

```
INFO 10-08 13:36:37 [__init__.py:239] No platform detected, vLLM is running on UnspecifiedPlatform
```
Intall the  vllm stack

```
helm repo add vllm https://vllm-project.github.io/production-stack
helm upgrade -i vllm vllm/vllm-stack -f vllm-prod-stack-values.yaml
```

**NOTE**: Pod startup took 250 seconds where 240seconds were from image pull for the router and pod statup took 6min with 4:15 of image pull for the model container.

**NOTE**: For a second autoscaled node. you might see the `running on UnspecifiedPlatform` error. Restarting the pod might sufice. Seem like a race condition betwen the pod and drivers installation.

# Consume the model

Check avaialble models

```
kubectl port-forward svc/vllm-router-service 30080:80
```
Or forwardin vLLM service directly offers similar endpoints

```
kb port-forward svc/vllm-opt125m-engine-service 30080:80
```
Check for available models

```
curl -s http://localhost:30080/v1/models | jq .

```

Autocomplete 
```
curl -s -X POST http://localhost:30080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
        "model": "facebook/opt-125m",
        "prompt": "Once upon a time, what happened in the US?",
        "max_tokens": 100
      }' | jq .
```

# Autoscaling

Deploying autoscaling components.

Once you have a model running you can set up the autoscaling components by running `setup.sh`
the script will deploy
- KEDA
- KEDA OTel Scaler & OTel Operator
- ScaledObject

**NOTE**: For Demo purposes the scaling is based on `vllm:current_qps` metric with a very low treshold. For Prod environments select more meaningfull metrics and tresholds. 

After the components are in place you can run `loadgeneration.sh`

It will port-forward the vllm router and send traffic
As a result you should see a new vLLM replica scheduled.


