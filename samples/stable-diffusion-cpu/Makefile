###############################
#		CONSTANTS
###############################
IMAGE ?= ghcr.io/kedify/stable-diffusion-cpu
WEBUI_IMAGE ?= ghcr.io/kedify/stable-diffusion-webui
CLUSTER_NAME ?= stable-diff
HACK_BIN ?= bin
VENDIR := $(abspath $(HACK_BIN)/vendir)

MINIO_USER := $(shell export LC_ALL=C; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)
MINIO_PASSWORD := $(shell export LC_ALL=C; tr -dc 'A-Za-z0-9!\#$%' </dev/urandom | head -c 15)

RABBITMQ_USER := $(shell export LC_ALL=C; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)
RABBITMQ_PASSWORD := $(shell export LC_ALL=C; tr -dc 'A-Za-z0-9!\#$%' </dev/urandom | head -c 15)

PROMPT ?= yellow submarine
NUM_IMAGES ?= 1


###############################
#		TARGETS
###############################
all: help

.PHONY: build-stable-diff-image
build-stable-diff-image: sync ## Builds the container image $(IMAGE).
	@$(call say,Build container image $(IMAGE))
	docker build . -t $(IMAGE)

.PHONY: build-webui-image
build-webui-image: ## Builds the container image $(WEBUI_IMAGE).
	@$(call say,Build container image $(WEBUI_IMAGE))
	cd webui && docker build . -t $(WEBUI_IMAGE)

.PHONY: run
run: ## Runs the built image.
	docker run -ti $(IMAGE)

.PHONY: run-example
run-example: ## Runs the built image and creates an example image. Usage: PROMPT="dog" NUM_IMAGES=2 make run-example
	@mkdir -p results
	docker run -ti --volume $(PWD)/results:/app/results $(IMAGE) --prompt "$(PROMPT)" --number_of_images $(NUM_IMAGES)
	@echo Done. Check the results directory.

.PHONY: deploy-minio
deploy-minio: ## Deploys minio into current Kubernetes context.
	@$(call say,Deploy Minio)
	helm repo add minio https://charts.min.io/
	@helm upgrade -i \
	minio minio/minio \
	--wait \
	--timeout=2m \
	-f minio-values.yaml \
	--set rootUser=$(MINIO_USER),rootPassword=$(MINIO_PASSWORD)

.PHONY: deploy-app
deploy-app: ## Deploys the fastsdcpu deployment and webui.
	@$(call say,Deploy stable diffusion app)
	kubectl apply -f manifests/app.yaml
	kubectl apply -f manifests/webapp.yaml
	kubectl wait --timeout=90s --for=condition=ready pod -lapp=stable-diffusion-webui
	kubectl wait --timeout=600s --for=condition=ready pod -lapp=stable-diffusion-cpu
	@echo the webapp should be available on http://localhost:8081

.PHONY: deploy-kafka
deploy-kafka: ## Deploys the strimzi operator and creates a kafka cluster with a single topic.
	@$(call say,Deploy Kafka)
	@kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
	kubectl wait --timeout=90s -nkafka --for=condition=ready pod -lname=strimzi-cluster-operator
	kubectl apply -f manifests/kafka.yaml
	kubectl wait --timeout=60s -nkafka --for=condition=ready pod -lstrimzi.io/name=stablediff-cluster-kafka
	kubectl wait --timeout=60s -nkafka --for=condition=ready pod -lstrimzi.io/component-type=entity-operator

.PHONY: deploy-rabbitmq
deploy-rabbitmq: ## Deploys rabbitmq.
	@$(call say,Deploy RabbitMQ)
	@kubectl create namespace rabbitmq --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
	kubectl wait --timeout=90s -nrabbitmq-system --for=condition=ready pod -lapp.kubernetes.io/name=rabbitmq-cluster-operator
	@cat manifests/default_user.conf.tmpl | RABBITMQ_USER=$(RABBITMQ_USER) RABBITMQ_PASSWORD=$(RABBITMQ_PASSWORD) envsubst > manifests/default_user.conf
	@kubectl create secret generic stablediff -nrabbitmq-system --from-file=manifests/default_user.conf --from-literal password=$(RABBITMQ_PASSWORD) --from-literal username=$(RABBITMQ_USER) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic stablediff-rabbitmq --from-literal host=amqp://$(RABBITMQ_USER):$(RABBITMQ_PASSWORD)@rabbitmq-cluster.rabbitmq-system.svc.cluster.local:5672 --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f manifests/rabbitmq.yaml
	kubectl wait --timeout=90s -nrabbitmq-system --for=condition=established crd/rabbitmqclusters.rabbitmq.com
	@while ! kubectl wait --timeout=90s -nrabbitmq-system --for=condition=ready pod -lapp.kubernetes.io/name=rabbitmq-cluster; do "echo waiting for rabbitmq.."; sleep 1; done

.PHONY: deploy-scaledobject
deploy-scaledobject: ## Deploys KEDA scaledobject.
	@$(call say,Deploy KEDA scaledobject)
	kubectl apply -f manifests/scaledobject.yaml

.PHONY: deploy
deploy: deploy-minio deploy-rabbitmq deploy-app ## Deploys minio and sample application.
	@$(call say,Deploy everything)

.PHONY: deploy-from-scratch
deploy-from-scratch: cluster import deploy ## Prepares also k3s cluster and deploys everything on it.

.PHONY: cluster
cluster: ## Creates simple k3d cluster with ingress controller (traefik).
	@$(call say,k3d cluster $(CLUSTER_NAME))
	k3d cluster create $(CLUSTER_NAME) -p "8081:80@loadbalancer"

.PHONY: import
import: ## Import images to k3d cluster to speed up the container creation.
	@$(call say,Import container images)
	k3d image import $(IMAGE) -c $(CLUSTER_NAME)
	k3d image import $(WEBUI_IMAGE) -c $(CLUSTER_NAME)

.PHONY: sync
sync: $(VENDIR) ## Syncs the rupeshs/fastsdcpu the repo.
	@$(call say,Sync upstream repo)
	$(VENDIR) sync

$(VENDIR): 
	@$(call say,Download vendir)
	mkdir -p $(HACK_BIN)
	curl -Ls https://carvel.dev/install.sh | K14SIO_INSTALL_BIN_DIR=$(HACK_BIN) bash
	@echo "vendir downloaded"

.PHONY: help
help: ## Show this help.
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

ifndef NO_COLOR
YELLOW=\033[0;33m
# no color
NC=\033[0m
endif

define say
echo "\n$(shell echo "$1 " | tr '[:rune:]' '=')\n $(YELLOW)$1$(NC)\n$(shell echo "$1 " | tr '[:rune:]' '=')"
endef
