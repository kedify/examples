FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go build -o load-generator main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/load-generator ./load-generator
EXPOSE 8080
CMD ["./load-generator"]
