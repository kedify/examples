APP_NAME := websocket-server
IMG := ghcr.io/kedify/sample-$(APP_NAME)

all: build

build:
	go build -o $(APP_NAME) main.go

docker-build:
	docker build -t $(IMG) .

docker-push:
	docker buildx build --output=type=registry --platform=linux/amd64,linux/arm64 -t $(IMG) .

patch-etc-hosts-file:
	@kubectl wait ingress/$(APP_NAME) --timeout=60s --for=jsonpath='{.status.loadBalancer.ingress}'
	@sudo sed -i.bak "/websocket.keda/d" /etc/hosts
	IP=$$(kubectl get ingress $(APP_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	echo "$${IP} websocket.keda" | sudo tee -a /etc/hosts
