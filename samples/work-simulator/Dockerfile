FROM golang:1.27.3-alpine@sha256:d530cf60723abf1ffae0cd16bb546b379ec0550d2f3815e5b16ed69dbc00fba4 AS builder
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