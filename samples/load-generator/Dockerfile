FROM golang:1.27.3-alpine@sha256:d530cf60723abf1ffae0cd16bb546b379ec0550d2f3815e5b16ed69dbc00fba4 AS builder
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go build -o load-generator main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/load-generator ./load-generator
EXPOSE 8080
CMD ["./load-generator"]
