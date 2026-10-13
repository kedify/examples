# Kedify vCluster + KPA demo

This repository creates a disposable Azure environment for demonstrating one
central Agent/KEDA/KPA installation scaling workloads in automatically
discovered vClusters. The prepared state contains two connected vClusters; the
third is created live to demonstrate discovery, bootstrap, registration, and
connection lifecycle. Redis runs in a second AKS cluster on the same virtual
network and is exposed through an internal load balancer.

## Topology

```text
Azure resource group
└── virtual network
    ├── main AKS: 3 x Standard_D8s_v5
    │   ├── Kedify Agent
    │   ├── KEDA
    │   ├── KPA
    │   ├── vCluster 1 (prepared)
    │   ├── vCluster 2 (prepared)
    │   └── vCluster 3 (created during the presentation)
    └── Redis AKS: 2 x Standard_D4s_v5
        └── Redis behind an internal load balancer
```

## Prerequisites

- Azure CLI authenticated with `az login`
- permission to create resource groups, role assignments, AKS, and network resources
- Helm, kubectl, the vCluster CLI, Make, and OpenSSL
- sufficient regional quota for 32 general-purpose vCPUs

Copy `.env.example` to `.env`, set `KEDIFY_ORG_ID` and `KEDIFY_API_KEY`, and
adjust the Azure region, Kubernetes version, or released chart version if
necessary. `KEDIFY_AGENT_ID` is optional; when omitted, Agent uses the
management cluster's immutable identity.

## Getting the kubeconfigs

This is the first step after cloning the repository when the Azure
infrastructure already exists. Log in to Azure, select the subscription that
contains the demo resource group, and download credentials for both physical
AKS clusters:

```bash
az login
az account show --output table
# If necessary:
az account set --subscription <subscription-id-or-name>

cp .env.example .env
# Configure RESOURCE_GROUP and DEPLOYMENT_NAME in .env if they differ from
# the defaults, then configure the Kedify credentials used by make platform.

make credentials
```

`make credentials` reads the main and Redis AKS names from the existing Bicep
deployment outputs and writes two separate files:

| File | Cluster | Used for |
| --- | --- | --- |
| `.kube/main.yaml` | management AKS | Agent/KEDA/KPA, vCluster Helm releases, registrations, and host-side connectivity checks |
| `.kube/redis.yaml` | Redis AKS | Redis deployment, queue manipulation, and Redis health checks |

The files are mode `0600`, are ignored by Git, and do not replace the user's
default kubeconfig. To confirm that the credentials point to the expected
clusters:

```bash
kubectl --kubeconfig .kube/main.yaml get nodes
kubectl --kubeconfig .kube/redis.yaml get nodes
```

You can add the main cluster kubeconfig to your current terminal

```
export KUBECONFIG=.kube/main.yaml
```

The ignored `state/` directory is also not included in a clone. After getting
the kubeconfigs for an existing deployment, reconstruct its Redis endpoint and
password from the Redis cluster:

```bash
make redis-state
```

This reads the existing `redis-auth` Secret and internal LoadBalancer Service,
then writes `state/redis-password` and `state/redis-ip` with mode `0600`. It
does not print the password. Only use this command from a trusted workstation;
access to `.kube/redis.yaml` grants access to the credential stored in the
cluster.

For a brand-new environment, `make infra` creates the Azure resources and
runs the same credential-download step automatically. Running
`make credentials` before the Bicep deployment exists will fail because there
are no deployment outputs from which to obtain the AKS names.

The demo deliberately does not store one kubeconfig per vCluster. Its helper
commands use the vCluster CLI with `.kube/main.yaml`, for example:

```bash
KUBECONFIG=.kube/main.yaml \
  vcluster connect vc-1 --namespace vcluster-1 \
  --background-proxy=false -- kubectl get nodes
```

This also mirrors the presentation topology: the vCluster control planes are
hosted in the management AKS cluster, while Agent discovers their credentials
and creates the `ClusterRegistration` resources consumed by KEDA and KPA.

## Deployment

Run each stage separately during development:

```bash
make infra
make platform
make vclusters
make redis
make verify
```

Or run the complete deployment:

```bash
make deploy
make verify
```

The deployment provisions infrastructure, installs released `kedify-agent`
chart `v0.8.2` (including its KEDA and KPA dependencies), discovers and
bootstraps two vClusters, and exposes Redis privately. It intentionally does
not create the third vCluster.

The management cluster hosts Agent, KEDA, KPA, and the vCluster control planes,
but it is not registered as a scaling target. Only automatically discovered
vClusters are reconciled by the dedicated multicluster runtime.

The management AKS cluster defaults to Kubernetes `1.35.8`, within KPA `0.2.1`'s
supported Kubernetes `1.33`–`1.35` range. Override
`MAIN_KUBERNETES_VERSION` only with another version supported by both AKS in
the selected region and the bundled KPA release.

## Presentation flow

Before the presentation, prepare and verify the stable two-cluster baseline:

```bash
make deploy
make prepare-scaling-demo
make verify
```

Create the third vCluster live:

```bash
make third-vcluster
```

This command first proves that the two existing registrations are Ready. It
then displays a live watch while Helm creates `vc-3`. The audience sees Agent
discover the vCluster, install the required KEDA/KPA CRDs, create the generated
kubeconfig Secret and `ClusterRegistration`, and finally report `Ready=True`.
Afterward, verify the complete three-cluster state with:

```bash
EXPECTED_VCLUSTERS=3 make verify
```

Then run the remote-scaling portion:

```bash
make present-scaling
```

The scaling presentation uses three independent Redis lists so demand and
autoscaling state cannot leak between vClusters:

| vCluster | Remote resource | Input | Expected result |
| --- | --- | --- | --- |
| `vc-1` | `ScaledObject` + KPA | 6 Redis items | 2 Deployment replicas |
| `vc-2` | authenticated `ScaledJob` | 3 Redis items | remote Jobs are created |
| `vc-3` | `ScaledObject` + KPA | 9 Redis items | 3 Deployment replicas |

### Scenario 1: an existing ScaledObject in vc-1

`make prepare-scaling-demo` creates a zero-replica `worker` Deployment, a
`TriggerAuthentication`, and a Redis-backed `ScaledObject` in `vc-1`. Central
KEDA resolves the authentication Secret through the `vc-1` remote client and
evaluates that cluster's Redis list. The trigger target is three list items per
replica, so six items produce a recommendation of two replicas. KPA is created
inside `vc-1` and applies the recommendation to the remote Deployment.

This scenario shows steady-state reconciliation for a vCluster that was
connected before the presentation:

```text
vc-1 ScaledObject -> central KEDA -> Redis list length (6)
                  -> remote KPA -> vc-1 Deployment (2 replicas)
```

### Scenario 2: an authenticated ScaledJob in vc-2

The prepared `vc-2` fixture is a `ScaledJob`, not a `ScaledObject`. Its
`TriggerAuthentication` reads the Redis address and password from a Secret in
`vc-2`. With a target of one queue item per Job, three items cause KEDA's
remote ScaledJob loop to create Jobs in `vc-2` (up to the configured maximum
of three). Each Job authenticates to Redis and removes one item with `RPOP`.
ScaledJobs do not create a KPA.

This separately demonstrates remote authentication lookup, Secret-based
scaler construction, and native KEDA Job creation:

```text
vc-2 ScaledJob -> central KEDA -> Redis list length (3)
                              -> Jobs in vc-2 -> RPOP one item per Job
```

### Scenario 3: immediate scaling after vc-3 discovery

`vc-3` does not exist in the prepared baseline. `make third-vcluster` creates
it live and waits while Agent discovers it, bootstraps its CRDs, and publishes
a ready registration. `make present-scaling` then creates a Deployment,
`TriggerAuthentication`, and `ScaledObject` in this newly registered cluster.
Nine items with the same three-items-per-replica target produce three replicas.

This combines the lifecycle and scaling stories: a newly discovered cluster
becomes usable by KEDA and KPA without restarting either controller or
manually supplying a kubeconfig.

```text
create vc-3 -> automatic registration -> remote ScaledObject
            -> central KEDA -> Redis list length (9)
                            -> remote KPA -> vc-3 Deployment (3 replicas)
```

After holding the scaled state for 20 seconds, the script clears the
`ScaledObject` queues and demonstrates scale-to-zero. Set
`DEMO_HOLD_SECONDS` to keep the scaled state visible for longer.

## How KEDA reaches Redis

Both AKS clusters are attached to the same Azure virtual network but use
different subnets:

```text
Azure VNet 10.10.0.0/16
├── main-aks subnet  10.10.0.0/20
│   ├── KEDA Pod
│   └── vCluster workload Pods
└── redis-aks subnet 10.10.16.0/24
    └── internal LoadBalancer -> Redis Service -> Redis Pod
```

The Redis Service has the Azure internal-load-balancer annotation, so Azure
assigns it a private frontend IP rather than a public address. No VNet peering
or cross-cluster Service DNS is involved: the clusters already share one VNet,
and clients connect directly to the internal load balancer's private IP on
port `6379`.

`make redis` waits for that private IP and stores it in `state/redis-ip`. It
also generates the Redis password in `state/redis-password`; both files are
ignored by Git. `make prepare-scaling-demo` first launches a temporary
`redis-cli` Pod in the main AKS cluster and requires a successful `PING`. This
proves the network path before any scaling resources are created.

The scripts then create a `redis-auth` Secret independently inside each
vCluster. The Secret contains the private address and password. For a
`ScaledObject`, central KEDA reads that Secret through the registered remote
Kubernetes client, builds the Redis scaler, and opens the TCP connection from
the KEDA Pod in the main cluster:

```text
vc-1/vc-3 Secret --read through remote API--> KEDA in main AKS
                                               |
                                               | TCP, private VNet, :6379
                                               v
                                      Redis internal load balancer
```

The Redis endpoint therefore must be reachable from the management cluster;
a Redis Service name that resolves only inside the Redis cluster would not
work. In the ScaledJob scenario, the Jobs also receive the private host and
password from their vCluster Secret and connect to the same internal load
balancer to consume queue items.

To rehearse the lifecycle again, remove only the third vCluster and its
generated registration:

```bash
make reset-third-vcluster
make verify
```

To remove the scaling resources and clear their Redis queues without deleting
the AKS clusters or vClusters:

```bash
make reset-scaling-demo
```

## Destruction

Destruction requires the resource-group name as an explicit guard:

```bash
CONFIRM_DESTROY=kedify-vcluster-kpa-demo make destroy
```
