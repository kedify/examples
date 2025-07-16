FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod .
COPY go.sum .
COPY main.go .
COPY kedify-loves-keda.gif .
RUN go build -o httpserver main.go

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/httpserver /httpserver
COPY --from=builder /app/kedify-loves-keda.gif /kedify-loves-keda.gif
CMD ["/httpserver"]