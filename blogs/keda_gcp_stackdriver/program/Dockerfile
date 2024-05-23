# Use the official Golang image to create a build artifact.
# This is based on Debian and sets the GOPATH to /go.
FROM golang:1.21.4 as builder

# Create and change to the app directory.
WORKDIR /app

# Retrieve application dependencies.
# This allows the container build to reuse cached dependencies.
# Copy the go module and sum files first to leverage Docker cache layering.
COPY go.mod go.sum ./
RUN go mod download

# Copy local code to the container image.
COPY . .

# Build the binary.
# -o myapp specifies the output file name, ensuring it's not prefixed with 'go-build'.
RUN CGO_ENABLED=0 GOOS=linux go build -v -o app

# Use a Docker multi-stage build to create a lean production image.
# https://docs.docker.com/develop/develop-images/multistage-build/
# Use the official Alpine image for a lean production container.
FROM alpine:latest  
RUN apk --no-cache add ca-certificates

# Copy the binary to the production image from the builder stage.
COPY --from=builder /app/app /app

# Run the web service on container startup.
CMD ["/app"]
