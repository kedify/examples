## Stable Diffusion use-case

![diagram](./demo.png "Diagram")
https://excalidraw.com/#json=p1f9nzyFye_sOgnV9AmIL,69oUi00h3HKXnsyzUReA5g

### try the container image locally

```
make build-image
PROMPT="cartoon dwarf" NUM_IMAGES=7 make run-example
```

### Deploy to K8s

```
make deploy
```

This deploys one replica of web ui, Minio, RabbitMQ and one replica of worker deployment that can generate the images.

## Common Pain Points

### Container images are too large

Reasons:
- the models are too large (~4 gigs)
- python

Mitigations:
- pre-fetch or even bake the container images on a newly spawned k8s nodes

### GPUs being too expensive
- https://cloud.google.com/spot-vms/pricing#gpu_pricing


### GKE Setup

#### two-nodes conventional k8s cluster with a GPU based elastic node pool

```
gcloud -q beta container clusters delete use-cases --zone us-east4-a --project "kedify-initial" --async
gcloud beta container --project "kedify-initial" clusters create "use-cases" \
   --no-enable-basic-auth \
   --cluster-version "1.28.8-gke.1095000" \
   --release-channel "regular" \
   --machine-type "e2-medium" \
   --image-type "COS_CONTAINERD" \
   --disk-type "pd-balanced" \
   --disk-size "100" \
   --metadata disable-legacy-endpoints=true \
   --spot \
   --num-nodes "2" \
   --logging=SYSTEM,WORKLOAD \
   --monitoring=SYSTEM \
   --enable-ip-alias \
   --network "projects/kedify-initial/global/networks/default" \
   --subnetwork "projects/kedify-initial/regions/us-east4/subnetworks/default" \
   --no-enable-intra-node-visibility \
   --default-max-pods-per-node "110" \
   --security-posture=disabled \
   --workload-vulnerability-scanning=disabled \
   --no-enable-master-authorized-networks \
   --addons HttpLoadBalancing,GcePersistentDiskCsiDriver \
   --enable-autoupgrade \
   --enable-autorepair \
   --max-surge-upgrade 1 \
   --max-unavailable-upgrade 0 \
   --binauthz-evaluation-mode=DISABLED \
   --enable-managed-prometheus \
   --node-locations "us-east4-a"

  # https://cloud.google.com/kubernetes-engine/docs/how-to/gpus#create-gpu-pool-auto-drivers
  gcloud beta container \
    --project "kedify-initial" node-pools create "gpu-pool" \
    --cluster "use-cases" \
    --machine-type "n1-standard-4" \
    --accelerator "type=nvidia-l4,count=1" \
    --image-type "UBUNTU_CONTAINERD" \
    --disk-type "pd-balanced" \
    --disk-size "150" \
    --metadata disable-legacy-endpoints=true \
    --node-taints nvidia.com/gpu=present:NoSchedule \
    --service-account "kedify-initial@kedify-initial.iam.gserviceaccount.com" \
    --spot \
    --num-nodes "1" \
    --enable-autoscaling \
    --total-min-nodes "1" \
    --total-max-nodes "2" \
    --scale-down-unneeded-time=1800s \
    --scan-interval=10s \
    --location-policy "ANY" \
    --max-surge-upgrade 0 \
    --max-unavailable-upgrade 1 \
    --max-pods-per-node "110" \
    --tags=nvidia-ingress-all \
    --node-locations "us-east4-a"

  gcloud container clusters update use-cases \
    --project "kedify-initial" \
    --zone us-east4-a \
    --enable-autoprovisioning \
    --min-cpu=1 --max-cpu=6 --min-memory=1 --max-memory=16 \
    --autoprovisioning-scopes=https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/compute

# login
gcloud container clusters get-credentials use-cases --zone us-east4-a --project kedify-initial
```

#### 1-node cluster with GPU enabled node

```
gcloud -q beta container clusters delete use-cases-single-node --zone us-east4-a --project "kedify-initial" --async
gcloud beta container clusters create use-cases-single-node \
  --project "kedify-initial" \
  --zone us-east4-a \
  --release-channel "regular" \
  --machine-type "n1-standard-4" \
  --accelerator "type=nvidia-tesla-t4,count=1,gpu-driver-version=default" \
  --image-type "UBUNTU_CONTAINERD" \
  --disk-type "pd-standard" \
  --disk-size "300" \
  --metadata disable-legacy-endpoints=true \
  --service-account "kedify-initial@kedify-initial.iam.gserviceaccount.com" \
  --spot \
  --no-enable-intra-node-visibility \
  --max-pods-per-node "110" \
  --num-nodes "1" \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --enable-ip-alias \
  --no-enable-intra-node-visibility \
  --default-max-pods-per-node "110" \
  --no-enable-master-authorized-networks \
  --tags=nvidia-ingress-all

gcloud container clusters update use-cases-single-node \
  --project "kedify-initial" \
  --zone us-east4-a \
  --enable-autoprovisioning \
  --min-cpu=1 --max-cpu=6 --min-memory=1 --max-memory=16 \
  --autoprovisioning-scopes=https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/compute


# login
gcloud container clusters get-credentials use-cases-single-node --zone us-east4-a --project kedify-initial

kubectl create ns gpu-operator
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-operator-quota
  namespace: gpu-operator
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

helm upgrade --install gpu-operator \
  -n gpu-operator \
  --create-namespace \
  nvidia/gpu-operator


# test that cuda is installed
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vectoradd
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-vectoradd
    image: "nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda11.7.1-ubuntu20.04"
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

### old way of installing the nvidia drivers

```
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml
```
