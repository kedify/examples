FROM golang:1.24 AS builder

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