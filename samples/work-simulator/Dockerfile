FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o work-simulator main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/work-simulator .
EXPOSE 8080
CMD ["./work-simulator"]