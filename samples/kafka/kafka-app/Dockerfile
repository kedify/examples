FROM golang:1.27.3@sha256:f20d83a83e18dbd2a4714b8ffd4b30b287b6243962dd75608e86abcc63ba4efc AS builder

WORKDIR /workspace

COPY Makefile Makefile
COPY go.mod go.mod
COPY go.sum go.sum

COPY cmd/ cmd/
COPY internal/ internal/
COPY vendor/ vendor/

RUN make build

FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /
COPY --from=builder /workspace/kafkaconsumerapp .
COPY --from=builder /workspace/kafkaproducerapp .

ENTRYPOINT ["/kafkaconsumerapp"]