FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY . .
RUN go build -o grpc-responder .

FROM gcr.io/distroless/static:nonroot

COPY --from=builder /app/grpc-responder /grpc-responder
CMD ["/grpc-responder"]