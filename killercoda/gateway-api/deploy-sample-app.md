In this step, you will deploy an application - trivial HTTP server, which will be used later for autoscaling. You will deploy two versions of this application `blue`{{}}, and `prpl`{{}}.

Lets start with a `Deployment`{{}} and `Service`{{}} for the `blue`{{}} version of our application:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blue
  namespace: default
spec:
  selector:
    matchLabels:
      app: blue
  template:
    metadata:
      labels:
        app: blue
    spec:
      containers:
        - name: mycontainer
          image: wozniakjan/simple-http
          env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: VERSION
              value: blue
---
apiVersion: v1
kind: Service
metadata:
  name: blue
  namespace: default
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: blue
  type: ClusterIP
EOF
```{{exec}}

And continue with a `Deployment`{{}} and `Service`{{}} for the `prpl`{{}} version of our application:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prpl
  namespace: default
spec:
  selector:
    matchLabels:
      app: prpl
  template:
    metadata:
      labels:
        app: prpl
    spec:
      containers:
        - name: mycontainer
          image: wozniakjan/simple-http
          env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: VERSION
              value: prpl
---
apiVersion: v1
kind: Service
metadata:
  name: prpl
  namespace: default
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: prpl
  type: ClusterIP
EOF
```{{exec}}

And finally a `HTTPRoute`{{}} to expose both versions `blue`{{}} and `prpl`{{}} as a single application with weighted load balancing feature of the Gateway API.
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: default
spec:
  hostnames:
  - keda-meets-gw.com
  parentRefs:
  - kind: Gateway
    namespace: envoy-gateway-system
    name: eg
  rules:
  - backendRefs:
    - kind: Service
      name: blue
      port: 8080
      weight: 1
    - kind: Service
      name: prpl
      port: 8080
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
EOF
```{{exec}}

So far these are all standard Kubernetes resources, KEDA is designed to plug into your application, your configuration, your workflow rather than force you to redesign your CI/CD pipelines.

The application is configured to receive requests for the URL `http://keda-meets-gw.com`{{}}, which will work only locally in the Killercoda environment. It may take some time for the envoy gateway controller to assign an IP address to the `HTTPRoute`{{}}.

The following snippet ensures that there is a matching entry in `/etc/hosts`{{}} so the URL `http://keda-meets-gw.com`{{}} can be resolved successfully.  In a real-world scenario, you would likely either create the DNS record manually or use the external-dns project with the `HTTPRoute`{{}} resource.
```
kubectl wait -nenvoy-gateway-system --for=jsonpath='{.status.addresses[0].value}' gateway/eg --timeout=5m
kubectl wait -ndefault --for=jsonpath='.status.parents[0].conditions[?(@.type=="Accepted")].status=True' httproute/app --timeout=5m
IP=$(kubectl get -nenvoy-gateway-system gateway eg -o json | jq --raw-output '.status.addresses[0].value')
echo "${IP} keda-meets-gw.com" >> /etc/hosts
```{{exec}}

Lets hit the endpoint of the appplication:
```
curl http://keda-meets-gw.com
curl http://keda-meets-gw.com
```{{exec}}

You should see similar reponse:
```bash
[blue]  -> [192.168.0.18]
[prpl]  -> [192.168.0.19]
```{{}}

You can also verify that all components of our application backend versions are running. There is are two `Deployments`{{}}, each with single `Pod`{{}} and `Service`{{}}. Then there is an `HTTPRoute`{{}} encapsulating both versions of the application.
```
kubectl get deployment -ndefault blue prpl
```{{exec}}

```
kubectl get pod -ndefault
```{{exec}}

```
kubectl get service -ndefault blue prpl
```{{exec}}

```
kubectl get httproute -ndefault app
```{{exec}}

There is a helpful script to run a curl in a few loops and display number of pods for each revision. Right now, because there is no autoscaling enabled yet, there will always be single replica for each version and the metrics will be empty. Half of the requests will be answered by `blue`{{}}, other half by `prpl`{{}} version of the application.

```
/scripts/benchmark.sh 1
```{{exec}}

In order to terminate the benchmark, hit:
```
# ctrl+c
```{{exec interrupt}}

Well done! Now you are ready to explore autoscaling with slightly more advanced routing topologies.

&nbsp;
&nbsp;

##### 3 / 5
