###############################
#		CONSTANTS
###############################
IMAGE ?= ghcr.io/kedify
VERSION	?= main
RENAISSANCE_VERSION=0.16.0
GIT_COMMIT ?= $(shell git rev-list -1 HEAD)
ARCH ?= $(shell uname -m)
ifeq ($(ARCH), x86_64)
	ARCH=amd64
endif


###############################
#		TARGETS
###############################
all: help

##@ Build

.PHONY: build-base-image
build-base-image: ## Builds the container (base) image for current arch.
	@$(call say,Build base container image)
	docker build . -f base.Dockerfile -t $(IMAGE)/azul-prime:21

renaissance-mit-$(RENAISSANCE_VERSION).jar:
	wget https://github.com/renaissance-benchmarks/renaissance/releases/download/v$(RENAISSANCE_VERSION)/renaissance-mit-$(RENAISSANCE_VERSION).jar

.PHONY: build-image
build-image: build-base-image renaissance-mit-$(RENAISSANCE_VERSION).jar ## Builds the container (app) image for current arch.
	@$(call say,Build app container image)
	docker build . -f app.Dockerfile -t $(IMAGE)/azul-app:$(VERSION)

.PHONY: build-images-multiarch
build-images-multiarch: ## Builds the container images for amd and arm arch and pushes them to container registry.
	@$(call say,Build container images (multiarch))
	docker buildx build . -f base.Dockerfile --push --platform linux/amd64,linux/arm64 -t $(IMAGE)/azul-prime:21
	docker buildx build . -f app.Dockerfile --push --platform linux/amd64,linux/arm64 -t $(IMAGE)/azul-app:$(VERSION)

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

###############################
#		HELPERS
###############################

ifndef NO_COLOR
YELLOW=\033[0;33m
# no color
NC=\033[0m
endif

define say
echo "\n$(shell echo "$1  " | sed s/./=/g)\n $(YELLOW)$1$(NC)\n$(shell echo "$1  " | sed s/./=/g)"
endef
