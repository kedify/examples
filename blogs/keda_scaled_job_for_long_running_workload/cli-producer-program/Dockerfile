# Use an official Ubuntu base image
FROM ubuntu:latest

# Update the package list
RUN apt-get update

# Install amqp-tools
RUN apt-get install -y amqp-tools && apt-get install -y curl

# Set the entrypoint to sh
ENTRYPOINT ["sh", "-c"]
