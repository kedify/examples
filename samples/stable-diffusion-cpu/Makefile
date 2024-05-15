###############################
#		CONSTANTS
###############################
IMAGE ?= ghcr.io/kedify/stable-diffusion-cpu
HACK_BIN ?= bin
VENDIR := $(abspath $(HACK_BIN)/vendir)

PROMPT ?= yellow submarine
NUM_IMAGES ?= 1


###############################
#		TARGETS
###############################

all: help

.PHONY: build-image
build-image: sync ## Builds the container image $(IMAGE).
	docker build . -t $(IMAGE)

.PHONY: run
run: ## Runs the built image.
	docker run -ti $(IMAGE)

.PHONY: run-example
run-example: ## Runs the built image and creates an example image. Usage: PROMPT="dog" NUM_IMAGES=2 make run-example
	@mkdir -p results
	docker run -ti --volume $(PWD)/results:/app/results $(IMAGE) --prompt "$(PROMPT)" --number_of_images $(NUM_IMAGES)
	@echo Done. Check the results directory.

.PHONY: deploy-minio
	helm upgrade -i \
	--set resources.requests.memory=512Mi \
	--set replicas=1 \
	--set persistence.enabled=true \
	--set mode=standalone \
	---set rootUser=rootuser,rootPassword=password123 \
	--generate-name minio/minio

.PHONY: sync
sync: $(VENDIR) ## Syncs the rupeshs/fastsdcpu the repo.
	$(VENDIR) sync

$(VENDIR): 
	@echo installing vendir
	mkdir -p $(HACK_BIN)
	curl -Ls https://carvel.dev/install.sh | K14SIO_INSTALL_BIN_DIR=$(HACK_BIN) bash

.PHONY: help
help: ## Show this help.
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
