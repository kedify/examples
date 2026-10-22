# docker buildx build . --push --platform linux/amd64,linux/arm64 -t ghcr.io/kedify/sample-minute-metrics:latest
FROM golang:1.27.3-alpine@sha256:d530cf60723abf1ffae0cd16bb546b379ec0550d2f3815e5b16ed69dbc00fba4
WORKDIR /app
COPY . .
RUN go build -o minute-metrics .

FROM gcr.io/distroless/static:nonroot
COPY --from=0 /app/minute-metrics /minute-metrics
CMD ["/minute-metrics"]
