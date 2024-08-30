FROM --platform=${BUILDPLATFORM} golang:1.22-alpine AS builder
ARG TARGETPLATFORM BUILDPLATFORM TARGETOS TARGETARCH
WORKDIR /app
COPY main.go .
COPY go.mod .
COPY go.sum .
COPY proto/ proto/
COPY helloservice/ helloservice/
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o grpc-responder .

FROM --platform=${TARGETPLATFORM} gcr.io/distroless/static:nonroot
COPY --from=builder /app/grpc-responder /grpc-responder
CMD ["/grpc-responder"]
