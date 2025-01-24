APP_NAME := work-simulator
IMG := ghcr.io/kedify/sample-$(APP_NAME)

all: build

build:
	go build -o $(APP_NAME) main.go

docker-build:
	docker build -t $(IMG) .

docker-push:
	docker buildx build --output=type=registry --platform=linux/amd64,linux/arm64 -t $(IMG) .
