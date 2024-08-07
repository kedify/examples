# Introduction to HTTP Scaler with Kedify

In this tutorial, we will explore the power of KEDA (Kubernetes Event-Driven Autoscaling) enhanced by Kedify, a tool that simplifies the installation and management of KEDA. You will learn how to effortlessly install KEDA using Kedify, scale an application based on HTTP request metrics, and understand the seamless integration of `Ingress`{{}} autowiring.

Kedify streamlines the process of installing and managing KEDA on your Kubernetes cluster. With a simple command, you can automate the entire lifecycle of managing KEDA including automated upgrades. Scaling applications in response to HTTP traffic is crucial for maintaining performance under varying loads. With KEDA's HTTP scaler, you can automatically adjust the number of running instances of your application based on the volume of incoming HTTP requests. This ensures that your application remains responsive during high traffic periods while optimizing resource usage during low traffic times.

Kedify further enhances KEDA's capabilities through `Ingress`{{}} autowiring. This feature simplifies the process of routing traffic to your application by automatically re-configuring existing `Ingress`{{}} resources. When you deploy your application, Kedify ensures that the necessary `Ingress`{{}} rules are matching the autoscaling setup, enabling seamless traffic flow without manual configuration. This autowiring capability mitigates the risk of misconfiguration, providing a smooth and automated experience for managing ingress in your Kubernetes environment and safe fallback with built-in recovery mechanism.

##### 1 / 4
