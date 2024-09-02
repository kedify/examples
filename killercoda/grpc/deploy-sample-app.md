In this step, you will deploy an application - trivial [gRPC server](https://github.com/kedify/examples/tree/main/samples/grpc-responder), which will be used later for autoscaling.

With gRPC, it's common practice to use TLS for the entire network path, we will generate one time self-signed certs.

```
mkcert grpc.keda
kubectl create secret tls grpc-responder --cert=grpc.keda.pem --key=grpc.keda-key.pem
```{{exec}}

Now lets create the `Deployment`{{}} mounting our TLS certificate and key:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grpc-responder
  namespace: default
  labels:
    app: grpc-responder
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grpc-responder
  template:
    metadata:
      labels:
        app: grpc-responder
    spec:
      containers:
      - name: grpc-responder
        image: ghcr.io/kedify/sample-grpc-responder
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 50051
        env:
        - name: RESPONSE_MESSAGE
          value: "Hello from Kedify"
        - name: TLS_ENABLED
          value: "true"
        - name: TLS_CERT_FILE
          value: "/certs/tls.crt"
        - name: TLS_KEY_FILE
          value: "/certs/tls.key"
        volumeMounts:
        - name: certs
          mountPath: /certs
      volumes:
      - name: certs
        secret:
          secretName: grpc-responder
EOF
```{{exec}}

Then a `Service`{{}}:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: grpc-responder
spec:
  selector:
    app: grpc-responder
  ports:
  - protocol: TCP
    port: 50051
    targetPort: 50051
  type: ClusterIP
EOF
```{{exec}}

And finally an `Ingress`{{}}:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grpc-responder
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grpc.keda
    secretName: grpc-responder
  rules:
  - host: grpc.keda
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grpc-responder
            port:
              number: 50051
EOF
```{{exec}}

So far these are all standard Kubernetes resources, KEDA is designed to plug into your application, your configuration, your workflow rather than force you to redesign your CI/CD pipelines.

The application is configured to receive requests for the URL `https://grpc.keda`{{}}, which will work only locally in the Killercoda environment. It may take some time for the ingress controller to assign an IP address to our `Ingress`{{}}.

The following snippet ensures that there is a matching entry in `/etc/hosts`{{}} so the URL `https://grpc.keda`{{}} can be resolved successfully. In a real-world scenario, you would likely either create the DNS record manually or use the external-dns project with the `Ingress`{{}} resource.
```
kubectl wait -ndefault --for=jsonpath='{.status.loadBalancer.ingress}' ingress/grpc-responder --timeout=5m
IP=$(kubectl get -ndefault ingress grpc-responder -o json | jq --raw-output '.status.loadBalancer.ingress[].ip')
echo "${IP} grpc.keda" >> /etc/hosts
```{{exec}}

Lets hit the endpoint of the appplication:
```
grpcurl -d '{"name": "Test"}' --authority grpc.keda grpc.keda:443 responder.HelloService/SayHello
```{{exec}}

You should see similar reponse:
```json
{
  "message": "Hello from Kedify"
}
```{{}}

You can also verify that all components of our application is running. There is a single `Deployment`{{}} with single `Pod`{{}}, `Service`{{}} and `Ingress`{{}} resources that you might expect in a standard simple backend application hosted on Kubernetes.
```
kubectl get deployment -ndefault grpc-responder
```{{exec}}

```
kubectl get pod -ndefault
```{{exec}}

```
kubectl get service -ndefault grpc-responder
```{{exec}}

```
kubectl get ingress -ndefault grpc-responder
```{{exec}}

Well done! Now you are ready to explore gRPC autoscaling and Kedify agent autowiring.

&nbsp;
&nbsp;

##### 3 / 4
