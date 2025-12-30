#!/bin/bash

# Usage: ./create_resources.sh <num_namespaces> <scaled_objects_per_ns> <scaled_jobs_per_ns> [namespace_prefix]

OTHER_DEPLOYMENTS=${OTHER_DEPLOYMENTS:-"0"}
OTHER_STATEFUL_SETS=${OTHER_STATEFUL_SETS:-"0"}

if [[ $# -lt 3 ]] || [[ $# -gt 4 ]]; then
    echo "Usage: $0 <num_namespaces> <scaled_objects_per_ns> <scaled_jobs_per_ns> [namespace_prefix]"
    exit 1
fi

num_namespaces=$1
scaled_objects_per_ns=$2
scaled_jobs_per_ns=$3
namespace_prefix=$4  # This is an optional parameter, it could be empty.

if [ -z "$namespace_prefix" ]; then
    namespace_prefix="namespace"
fi

echo "Deploying ${num_namespaces} namespaces"
for (( n=1; n<=num_namespaces; n++ )); do
    namespace="${namespace_prefix}-${n}"
    echo "> namespace: ${namespace}"
    kubectl create namespace $namespace >/dev/null 2>&1 &

    # Create Metrics Source Deployment and Service in parallel
    (
        kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kedify-sample-minute-metrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kedify-sample-minute-metrics
  template:
    metadata:
      labels:
        app: kedify-sample-minute-metrics
    spec:
      containers:
      - name: kedify-sample-minute-metrics
        image: ghcr.io/kedify/sample-minute-metrics:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        env:
        - name: SCHEDULE
          value: "0:8,1:0,2:4,3:2,4:0,5:3,7:5,9:0"
EOF

        kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: Service
metadata:
  name: kedify-sample-minute-metrics
spec:
  selector:
    app: kedify-sample-minute-metrics
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
EOF
        echo "  - Metrics source deployed"
    ) &

    echo "  - Deploying ${scaled_objects_per_ns} scaled objects"
    for (( x=1; x<=scaled_objects_per_ns; x++ )); do
        # Create Deployment and ScaledObject for each instance in parallel
        (
            kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kedify-sample-app-$x
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kedify-sample-app-$x
  template:
    metadata:
      labels:
        app: kedify-sample-app-$x
    spec:
      containers:
      - name: nginx-container
        image: nginx:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
EOF

            kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kedify-sample-so-$x
spec:
  scaleTargetRef:
    name: kedify-sample-app-$x
  pollingInterval: $((10 + x))
  cooldownPeriod: 5
  minReplicaCount: $((x % 5))
  maxReplicaCount: $((10 + x % 5))
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 15
        scaleDown:
          stabilizationWindowSeconds: 15
  triggers:
  - type: metrics-api
    metadata:
      url: "http://kedify-sample-minute-metrics.$namespace.svc.cluster.local/api/v1/minutemetrics"
      valueLocation: "value"
      targetValue: '$((x + 1))'
EOF
        ) &
    done

    echo "  - Deploying ${scaled_jobs_per_ns} scaled jobs"
    for (( y=1; y<=scaled_jobs_per_ns; y++ )); do
        # Create each ScaledJob in parallel
        (
            kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: kedify-sample-sj-$y
spec:
  jobTargetRef:
    template:
      spec:
        containers:
        - name: busybox-worker
          image: busybox
          args:
          - /bin/sh
          - -c
          - sleep 30
          imagePullPolicy: IfNotPresent
        restartPolicy: Never
  pollingInterval: $((30 + y))
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  maxReplicaCount: $((10 + y % 5))
  triggers:
  - type: metrics-api
    metadata:
      url: "http://kedify-sample-minute-metrics.$namespace.svc.cluster.local/api/v1/minutemetrics"
      valueLocation: "value"
      targetValue: '$((12 + y * 2))'
EOF
        ) &
    done

    echo "  - Deploying ${OTHER_DEPLOYMENTS} other deployments"
    for (( x=1; x<=${OTHER_DEPLOYMENTS}; x++ )); do
        # Create other Deployments simulating normal user workloads
        (
            kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: some-other-app-$x
spec:
  replicas: 1
  selector:
    matchLabels:
      app: some-other-app-$x
  template:
    metadata:
      labels:
        app: some-other-app-$x
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:latest
        imagePullPolicy: IfNotPresent
EOF
        ) &
    done

    echo "  - Deploying ${OTHER_STATEFUL_SETS} other stateful sets"
    for (( x=1; x<=${OTHER_STATEFUL_SETS}; x++ )); do
        # Create other Deployments simulating normal user workloads
        (
            kubectl apply -n $namespace -f - <<EOF >/dev/null 2>&1
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: some-other-stateful-app-$x
spec:
  replicas: 1
  selector:
    matchLabels:
      app: some-other-stateful-app-$x
  template:
    metadata:
      labels:
        app: some-other-stateful-app-$x
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:latest
        imagePullPolicy: IfNotPresent
EOF
        ) &
    done

    # Notification for complete namespace setup
    wait
    echo "  - All resources deployed in ${namespace} ns"
done

wait
echo "All namespaces have been set up."
