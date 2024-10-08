In this step, you will deploy an application - trivial HTTP server, which will be used later for autoscaling.

Lets start with a `Deployment`{{}}:
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
EOF
```{{exec}}

Then a `Service`{{}}:
```yaml
cat << 'EOF' | kubectl apply -f -
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

And finally an `Ingress`{{}}:
```yaml
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blue
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: blue.com
    http:
      paths:
      - backend:
          service:
            name: blue
            port:
              number: 8080
        path: /
        pathType: Prefix
EOF
```{{exec}}

So far these are all standard Kubernetes resources, KEDA is designed to plug into your application, your configuration, your workflow rather than force you to redesign your CI/CD pipelines.

The application is configured to receive requests for the URL `http://blue.com`{{}}, which will work only locally in the Killercoda environment. It may take some time for the ingress controller to assign an IP address to our `Ingress`{{}}.

The following snippet ensures that there is a matching entry in `/etc/hosts`{{}} so the URL `http://blue.com`{{}} can be resolved successfully.  In a real-world scenario, you would likely either create the DNS record manually or use the external-dns project with the `Ingress`{{}} resource.
```
kubectl wait -ndefault --for=jsonpath='{.status.loadBalancer.ingress}' ingress/blue --timeout=5m
IP=$(kubectl get -ndefault ingress blue -o json | jq --raw-output '.status.loadBalancer.ingress[].ip')
echo "${IP} blue.com" >> /etc/hosts
```{{exec}}

Lets hit the endpoint of the appplication:
```
curl http://blue.com
```{{exec}}

You should see similar reponse:
```bash
[blue]  -> [192.168.0.18]
```{{}}

You can also verify that all components of our application is running. There is a single `Deployment`{{}} with single `Pod`{{}}, `Service`{{}} and `Ingress`{{}} resources that you might expect in a standard simple backend application hosted on Kubernetes.
```
kubectl get deployment -ndefault blue
```{{exec}}

```
kubectl get pod -ndefault
```{{exec}}

```
kubectl get service -ndefault blue
```{{exec}}

```
kubectl get ingress -ndefault blue
```{{exec}}

Well done! Now you are ready to explore HTTP autoscaling and Kedify agent autowiring.

&nbsp;
&nbsp;

##### 3 / 4
