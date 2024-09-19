FROM golang AS builder
COPY . .
RUN go build -o /tmp/server ./main.go

FROM ubuntu
COPY --from=builder /tmp/server /bin/server
COPY index.html /var/www/html/index.html
CMD ["/bin/server"]
