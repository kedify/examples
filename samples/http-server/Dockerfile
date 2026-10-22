FROM golang:1.27.3-alpine@sha256:d530cf60723abf1ffae0cd16bb546b379ec0550d2f3815e5b16ed69dbc00fba4 AS builder
WORKDIR /app
COPY go.mod .
COPY go.sum .
COPY vendor/ ./vendor/
COPY main.go .
COPY kedify-loves-keda.gif .
RUN go build -mod=vendor -o httpserver main.go

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/httpserver /httpserver
COPY --from=builder /app/kedify-loves-keda.gif /kedify-loves-keda.gif
CMD ["/httpserver"]