# Using `kedify-http` Scaler with HTTP Headers

This example demonstrates how to use the `kedify-http` scaler with HTTP headers to scale a Kubernetes deployment based on incoming HTTP requests.

The default manifests use exact header values. For wildcard and regular expression values, follow the [header patterns example](#wildcard-and-regular-expression-values) below.

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

## Wildcard and Regular Expression Values

Use a Kedify installation whose KEDA, HTTP add-on, and Agent releases support `valueWildcard` and `valueRegex`. The minimum version listed above applies to exact values only. Upgrade the `HTTPScaledObject` CRD along with the components; updating container images alone does not update its schema. Verify that the new fields are available:

```sh
kubectl explain httpscaledobject.spec.headers.valueWildcard
kubectl explain httpscaledobject.spec.headers.valueRegex
```

From this directory, deploy the applications and apply the alternative selectors:

```sh
kubectl -n default apply -f manifests.yaml
kubectl -n default apply -f header-patterns.yaml
kubectl -n default wait --for=condition=Ready scaledobject/foo scaledobject/bar scaledobject/http-server --timeout=120s
```

`header-patterns.yaml` replaces the `foo` and `bar` ScaledObjects from `manifests.yaml`. Their Deployments and Services are reused, and `http-server` keeps its headerless fallback route. All three routes use host `demo.keda` and path prefix `/`.

The `foo` route uses a wildcard value:

```yaml
headers: |
  [{"name": "User-Agent", "valueWildcard": "Python*"}]
```

The `bar` route combines a regular expression with an exact value. Both headers must match:

```yaml
headers: |
  [
    {"name": "User-Agent", "valueRegex": "Go/[0-9]+(\\.[0-9]+)*"},
    {"name": "X-Environment", "value": "Prod"}
  ]
```

Header names are fixed and case-insensitive. Each entry must specify exactly one of `value`, `valueWildcard`, or `valueRegex`:

- `value` matches literally and is case-sensitive, so `Prod` and `prod` differ.
- `valueWildcard` matches the whole value case-insensitively. `*` matches zero or more characters, and `?` matches exactly one character. Other characters are literal: `rel.v?-*stable` matches `REL.V2-ALPHA.STABLE` but not `relxv2-alpha.stable`. A value of `*` requires the header to be present and also matches an empty value.
- `valueRegex` uses RE2 syntax and matches the whole value case-insensitively. The expression above matches `Go/1`, `Go/1.22.0`, and `gO/1.22.0`, but not `Go/1.22.0-extra`. JSON needs `\\` to represent one backslash, so `\\.` in the metadata becomes `\.` in the regex and matches a literal dot.

All entries in `headers` must match. A request that matches neither selected route goes to `http-server`.

### Try the Patterns

After the agent creates the proxy Service, forward its port in another terminal:

```sh
kubectl -n default port-forward svc/kedify-proxy 8080:8080
```

For an installation with a cluster-wide proxy, use its namespace (typically `keda`) in place of `default`.

Run the following requests. Each `/info` response includes `POD_NAME`, which identifies the selected Deployment:

```sh
# Wildcard: routes to foo, including a mixed-case value.
curl -H 'Host: demo.keda' -H 'User-Agent: pYtHoN/3.12' http://localhost:8080/info

# Wildcard: * can match zero characters, so this also routes to foo.
curl -H 'Host: demo.keda' -H 'User-Agent: Python' http://localhost:8080/info

# Regex and exact header: routes to bar.
curl -H 'Host: demo.keda' -H 'User-Agent: gO/1.22.0' -H 'X-Environment: Prod' http://localhost:8080/info

# The exact value is case-sensitive: routes to http-server.
curl -H 'Host: demo.keda' -H 'User-Agent: Go/1.22.0' -H 'X-Environment: prod' http://localhost:8080/info

# A missing required header also routes to http-server.
curl -H 'Host: demo.keda' -H 'User-Agent: Go/1.22.0' http://localhost:8080/info

# Regex matches the whole value: trailing characters route to http-server.
curl -H 'Host: demo.keda' -H 'User-Agent: Go/1.22.0-extra' -H 'X-Environment: Prod' http://localhost:8080/info

# No User-Agent header: routes to http-server.
curl -H 'Host: demo.keda' -H 'User-Agent:' http://localhost:8080/info
```

With no traffic, the Deployments scale to zero. The next matching request activates its selected Deployment. Repeat the requests while the applications are running to exercise warm routing too.

To restore the original exact-value selectors, reapply `manifests.yaml`. To remove the sample:

```sh
kubectl -n default delete -f manifests.yaml
```

For more information, see [routing traffic with HTTP headers](https://docs.kedify.io/reference/http-scaler/#routing-traffic-with-http-headers).
