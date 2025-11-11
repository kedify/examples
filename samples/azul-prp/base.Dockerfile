# docker buildx build . -f base.Dockerfile --push --platform linux/amd64,linux/arm64 -t ghcr.io/kedify/azul-prime:21
# Use Azul Prime JDK 21 as the base image
FROM --platform=$TARGETARCH azul/prime:21
# Install Python 3 and pip
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
# Install jmxquery via pip
RUN pip3 install --no-cache-dir jmxquery
# Verify installations
RUN python3 --version && pip3 show jmxquery
COPY --chmod=0755 ready.py /
