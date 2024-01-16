# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Install curl
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Copy the Python script into the container at /usr/src/app
COPY . .

RUN pip install --no-cache-dir -r requirements.txt

# Run app.py when the container launches
CMD ["python", "-u","./app.py"]
