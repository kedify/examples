#!/bin/bash

currentMessage=""

# Function to handle SIGTERM
handle_sigterm() {
    if [ -n "$currentMessage" ]; then
        echo "SIGTERM signal received while processing a message."
        curl -X POST http://localhost:8080/kill/count -s
        echo "Kill count HTTP request sent."
    else
        echo "SIGTERM signal received, but no message was being processed."
    fi
    exit 0
}

# Setting up a trap for SIGTERM
trap 'handle_sigterm' SIGTERM

echo "Waiting for message...\n"
currentMessage=$(amqp-consume --url="$RABBITMQ_URL" -q "testqueue" -c 1 cat)
echo "Message received, processing: $currentMessage"

i=1
while [ $i -le 360 ]; do
    echo "Sleeping second $i"
    sleep 1
    i=$((i+1))
done

# Reset currentMessage after processing is complete
currentMessage=""

curl -X POST http://result-analyzer-service:8080/create/count -s
