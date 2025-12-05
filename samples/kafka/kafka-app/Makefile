APP_NAME := kafka-app
IMG := ghcr.io/kedify/sample-$(APP_NAME)

ARCH       ?=amd64
TARGET_OS  ?=linux

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

.PHONY: build
build: producer consumer

.PHONY: producer
producer:
	go build -o kafkaproducerapp cmd/kafkaproducerapp/main.go

.PHONY: consumer
consumer:
	go build -o kafkaconsumerapp cmd/kafkaconsumerapp/main.go

.PHONY: docker-build
docker-build:
	docker build -t $(IMG) .

.PHONY: docker-push
docker-push:
	docker buildx build --output=type=registry --platform=linux/amd64,linux/arm64 -t $(IMG) .

# Legacy targets for backward compatibility
.PHONY: image
image: docker-build docker-push

.PHONY: image-build
image-build: docker-build

.PHONY: image-push
image-push: docker-push