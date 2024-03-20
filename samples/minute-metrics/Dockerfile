FROM golang:1.22-alpine
WORKDIR /app
COPY . .
RUN go build -o minute-metrics .

FROM gcr.io/distroless/static:nonroot
COPY --from=0 /app/minute-metrics /minute-metrics
CMD ["/minute-metrics"]
