# Healthchecks for AWS Probes

The `kedify-http` scaler uses the `Host` header during proxying to route traffic to the correct deployment. However,
AWS Load Balancer healthcheck probes set the IP address of a particular `kedify-proxy` pod as the `Host` header.
For this reason, there are options for this scaler to ensure that the healthcheck probes are routed to the correct deployment
through unique path prefixes embedding the `Host` in the path.
```
healthcheckResponse: pathEmbeddedHost
healthcheckPathPrefix: /kedify-proxy/[Host]
```

## Prerequisites
- Kubernetes cluster
- Kedify installed with addon version at least `v0.10.0-6`

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

Also deployment for `http-server` along with a single `kedify-proxy` deployment.
```
$ kubectl get deployments
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
http-server    1/1     1            1           22s
kedify-proxy   1/1     1            1           21s
```

And a single `ScaledObject` resources with healthcheck path configured:
```
$ kubectl get so
NAME           SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED    TRIGGERS   AUTHENTICATIONS   AGE
http-server    apps/v1.Deployment   http-server       0     5     True    False    False      Unknown                                31s
```

## Test the Application
For convenience, set proper entries in `/etc/hosts` file:
```
make patch-etc-hosts-file
```

This will allow you to access the application using `demo.keda` hostname:
```
$ curl http://demo.keda/info
delay config:  {FixedDelay:0s IsRange:false MinDelay:0 MaxDelay:0}
POD_NAME:      http-server-77ddd5fc5b-rhzjf
POD_NAMESPACE: default
POD_IP:        10.42.0.23
```

The same response can be reached through the `kedify-proxy` service directly on the healthcheck path `kedify-proxy/demo.keda/info` even with the `Host` header set to `localhost`:
```
$ kubectl port-forward svc/kedify-proxy 8080:8080
$ curl -H 'Host: localhost' http://localhost:8080/kedify-proxy/demo.keda/info
delay config:  {FixedDelay:0s IsRange:false MinDelay:0 MaxDelay:0}
POD_NAME:      http-server-77ddd5fc5b-rhzjf
POD_NAMESPACE: default
POD_IP:        10.42.0.23
```

For more information, check https://kedify.io/documentation/scalers/http-scaler/#healthchecks-for-aws-probes
