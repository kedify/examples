APP_NAME := http-server

.PHONY: all
all: deploy patch-etc-hosts-file

.PHONY: deploy
deploy:
	kubectl apply -f manifests.yaml

.PHONY: patch-etc-hosts-file
patch-etc-hosts-file:
	@kubectl wait ingress/$(APP_NAME) --timeout=60s --for=jsonpath='{.status.loadBalancer.ingress}'
	@kubectl wait ingress --for='jsonpath={.spec.rules[0].http.paths[0].backend.service.name}=kedify-proxy' http-server
	@sudo sed -i.bak "/demo.keda/d" /etc/hosts
	IP=$$(kubectl get ingress $(APP_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	echo "$${IP} demo.keda" | sudo tee -a /etc/hosts
