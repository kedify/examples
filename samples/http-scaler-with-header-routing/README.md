# Using `kedify-http` Scaler with HTTP Headers

This example demonstrates how to use the `kedify-http` scaler with HTTP headers to scale a Kubernetes deployment based on incoming HTTP requests.

## Prerequisites
- Kubernetes cluster
- Kedify installed with addon version at least `v0.10.0-7`

## Deploy Sample Application

```
make deploy
```

There is a single ingress resource created with the name `http-server` as an endpoint for the application:
```
$ kubectl get ingress
NAME          CLASS     HOSTS       ADDRESS      PORTS   AGE
http-server   traefik   demo.keda   172.18.0.2   80      21s
```

There are three versions of the same application - `http-server`, with `foo` and` bar` - and one `kedify-proxy` deployment.
```
$ kubectl get deployments
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
bar            0/0     0            0           22s
foo            0/0     0            0           22s
http-server    0/0     0            0           22s
kedify-proxy   1/1     1            1           21s
```

There are also three `ScaledObject` resources, one for each version of the application:
```
$ kubectl get so
NAME           SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED    TRIGGERS   AUTHENTICATIONS   AGE
bar            apps/v1.Deployment   bar               0     5     True    False    False      Unknown                                31s
foo            apps/v1.Deployment   foo               0     5     True    False    False      Unknown                                31s
http-server    apps/v1.Deployment   http-server       0     5     True    False    False      Unknown                                31s
```

They all have `kedify-http` scaler defined as a trigger. The `foo` and `bar` also contain an HTTP header match condition for `app: foo` and `app: bar` respectively.

## Test the Application
For convenience, set proper entries in `/etc/hosts` file:
```
make patch-etc-hosts-file
```
This will allow you to access the application using `demo.keda` hostname.

Without setting `app` header to either `foo` or `bar`, the request will be routed to `http-server` deployment:
```
$ curl http://demo.keda/info
delay config:  {FixedDelay:0s IsRange:false MinDelay:0 MaxDelay:0}
POD_NAME:      http-server-77ddd5fc5b-n47g4
POD_NAMESPACE: default
POD_IP:        10.42.0.39
```

With `app: foo` header, the request will be routed to `foo` deployment:
```
$ curl -H "app: foo" http://demo.keda/info
delay config:  {FixedDelay:0s IsRange:false MinDelay:0 MaxDelay:0}
POD_NAME:      foo-7d74cf8fc6-nnglk
POD_NAMESPACE: default
POD_IP:        10.42.0.41
```

With `app: bar` header, the request will be routed to `bar` deployment:
```
$ curl -H "app: bar" http://demo.keda/info
delay config:  {FixedDelay:0s IsRange:false MinDelay:0 MaxDelay:0}
POD_NAME:      bar-7fccc97f85-8st2n
POD_NAMESPACE: default
POD_IP:        10.42.0.43
```

For more information, check https://kedify.io/documentation/scalers/http-scaler/#routing-traffic-with-http-headers
