# docker buildx build . --push --platform linux/amd64,linux/arm64 -t ghcr.io/kedify/sample-minute-metrics:latest
FROM golang:1.22-alpine
WORKDIR /app
COPY . .
RUN go build -o minute-metrics .

FROM gcr.io/distroless/static:nonroot
COPY --from=0 /app/minute-metrics /minute-metrics
CMD ["/minute-metrics"]
