APP_NAME := rollouts-demo

.PHONY: all
all: deploy patch-etc-hosts-file

.PHONY: deploy
deploy:
	kubectl apply -f manifests.yaml

.PHONY: patch-etc-hosts-file
patch-etc-hosts-file:
	@kubectl wait ingress/$(APP_NAME) --timeout=60s --for=jsonpath='{.status.loadBalancer.ingress}'
	@kubectl wait ingress --for='jsonpath={.spec.rules[0].http.paths[0].backend.service.name}=kedify-proxy' $(APP_NAME)
	@sudo sed -i.bak "/demo.keda/d" /etc/hosts
	@IP=$$(kubectl get ingress $(APP_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	HOSTNAME=$$(kubectl get ingress $(APP_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); \
	if [ -n "$${IP}" ]; then \
		echo "$${IP} demo.keda" | sudo tee -a /etc/hosts; \
	elif [ -n "$${HOSTNAME}" ]; then \
		echo "Ingress $(APP_NAME) exposes hostname '$${HOSTNAME}' but no numeric IP. Resolve it (e.g. 'getent hosts $${HOSTNAME}') and add the result to /etc/hosts manually." >&2; \
		exit 1; \
	else \
		echo "Ingress $(APP_NAME) has no loadBalancer ip or hostname yet — your Ingress controller probably hasn't assigned an external address." >&2; \
		exit 1; \
	fi
