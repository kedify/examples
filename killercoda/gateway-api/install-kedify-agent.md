The Kedify agent is an application designed to simplify deployment and management of KEDA seamlessly within your Kubernetes environment. For the purposes of the scenario here in Killercoda, you will use the pre-installed [Kedify kubectl plugin](https://github.com/jkremser/kubectl-kedify). You can click on the command below, it will get automatically executed in the terminal on the right part of the screen.
```bash
kubectl kedify install --email keda-meets-gw@killercoda.com -y
```{{exec}}

The agent also enhances KEDA capabilities with additional features. In scope of this scenario, you are going to learn about the HTTP scaler with streamlined management of `HTTPRoute`{{}} resources.

> Learn more about the Kedify HTTP Scaler -> https://kedify.io/scalers/http

After the agent is deployed, it will install KEDA and other necessary dependencies, you can observe all getting installed with:
```bash
watch -n1 --color kubecolor --force-colors get deployments -nkeda
```{{exec}}


Deployed KEDA should look similar to this, it may take around 1 to 2 minutes for all KEDA parts to become fully ready
```bash
NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
keda-add-ons-http-controller-manager   1/1     1            1           81s
keda-add-ons-http-external-scaler      1/1     1            1           81s
keda-add-ons-http-interceptor          1/1     1            1           81s
keda-admission-webhooks                1/1     1            1           83s
keda-operator                          1/1     1            1           83s
keda-operator-metrics-apiserver        1/1     1            1           83s
kedify-agent                           1/1     1            1           99s
metrics-server                         1/1     1            1           88s
```{{}}

The agent installed metrics server, latest KEDA and HTTP Add-On. To stop the `watch`{{}} loop, you can just hit:
```
# ctrl+c
```{{exec interrupt}}

> The official KEDA documentation is a great resource of information if you are curious to learn more about the fundamental building blocks, architecture and best practices, check out https://keda.sh/docs/2.15/concepts.

When you have finished agent installation and exploring the KEDA deployments, click on the `CHECK`{{}} button on the bottom to move to the next step.

&nbsp;
&nbsp;

##### 2 / 5
