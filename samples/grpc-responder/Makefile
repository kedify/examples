APP_NAME := grpc-responder
IMG := ghrc.io/kedify/sample-$(APP_NAME)
PROTO_SRC := proto/service.proto
PROTO_GEN_DIR := ./proto
GOPATH_BIN := $(shell go env GOPATH)/bin
CERT_FILE := server.crt
KEY_FILE := server.key
SAN_FILE := san.ext

# Default values for environment variables
DEFAULT_PORT := 50051
DEFAULT_DELAY := 0.5
DEFAULT_MESSAGE := "Hello from Kedify"
DEFAULT_TLS_ENABLED := false

all: proto build

proto:
	PATH=$(GOPATH_BIN):$$PATH protoc --go_out=$(PROTO_GEN_DIR) --go-grpc_out=$(PROTO_GEN_DIR) $(PROTO_SRC)

build: proto
	go build -o $(APP_NAME) main.go

certs:
	openssl genpkey -algorithm RSA -out $(KEY_FILE)
	openssl req -new -key $(KEY_FILE) -out server.csr -subj "/CN=localhost"
	echo "subjectAltName=DNS:localhost,DNS:grpc.keda,IP:127.0.0.1" > $(SAN_FILE)
	openssl x509 -req -in server.csr -signkey $(KEY_FILE) -out $(CERT_FILE) -days 365 -extfile $(SAN_FILE)
	rm -f server.csr $(SAN_FILE)

run: build certs
	PORT=$${PORT:-$(DEFAULT_PORT)} \
	RESPONSE_DELAY=$${RESPONSE_DELAY:-$(DEFAULT_DELAY)} \
	RESPONSE_MESSAGE=$${RESPONSE_MESSAGE:-$(DEFAULT_MESSAGE)} \
	TLS_ENABLED=$${TLS_ENABLED:-$(DEFAULT_TLS_ENABLED)} \
	TLS_CERT_FILE=$(CERT_FILE) \
	TLS_KEY_FILE=$(KEY_FILE) \
	./$(APP_NAME)

docker-build:
	docker build -t $(IMG) .

docker-publish-multiarch:
	docker buildx build --output=type=registry --platform=linux/amd64,linux/arm64 . -t $(IMG)

docker-run:
	docker run -p 50051:50051 \
		-e PORT=$${PORT:-$(DEFAULT_PORT)} \
		-e RESPONSE_DELAY=$${RESPONSE_DELAY:-$(DEFAULT_DELAY)} \
		-e RESPONSE_MESSAGE=$${RESPONSE_MESSAGE:-$(DEFAULT_MESSAGE)} \
		-e TLS_ENABLED=$${TLS_ENABLED:-$(DEFAULT_TLS_ENABLED)} \
		-e TLS_CERT_FILE=/certs/$(CERT_FILE) \
		-e TLS_KEY_FILE=/certs/$(KEY_FILE) \
		-v $(PWD):/certs \
		$(IMG)

clean:
	rm -f $(APP_NAME) $(CERT_FILE) $(KEY_FILE)
	rm -rf $(PROTO_GEN_DIR)/*.pb.go

.PHONY: all proto build certs run docker-build docker-run clean
