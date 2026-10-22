FROM --platform=${BUILDPLATFORM} golang:1.27.3-alpine@sha256:d530cf60723abf1ffae0cd16bb546b379ec0550d2f3815e5b16ed69dbc00fba4 AS builder
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
