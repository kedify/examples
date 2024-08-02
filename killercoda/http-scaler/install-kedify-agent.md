# Kedify Agent

For your production grade scenarios, you will want to create account in https://dashboard.kedify.io/.

But for the purposes of the scenario here in Killercoda, it's perfectly fine to install Kedify agent with "mock" account:
```
yes | kubectl kedify install --email http-scaler@killercoda.com
```{{}}

TODO: elaborate this

Watch agent and KEDA getting installed:
```
kubectl get po -nkeda -w
```
