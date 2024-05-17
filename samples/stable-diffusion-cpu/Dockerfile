# chainguard
# FROM cgr.dev/chainguard/python:latest-dev as builder
# WORKDIR /app
# COPY requirements.txt .
# RUN pip install torch==2.2.2 --index-url https://download.pytorch.org/whl/cpu --user && \
#     pip install -r requirements.txt --user

# FROM cgr.dev/chainguard/python:latest
# WORKDIR /app

# COPY --from=builder /home/nonroot/.local/lib/python3.12/site-packages /home/nonroot/.local/lib/python3.12/site-packages
# COPY --chown=65532:65532 fastsdcpu/ /app
# USER 65532:65532

FROM python:3.9
WORKDIR /app
COPY requirements.txt .
# USER 65532:65532
COPY --chown=65532:65532 fastsdcpu/ /app
COPY requirements.txt .
COPY tweaks/consumer.sh /app
RUN pip --no-cache-dir install torch==2.2.2 --index-url https://download.pytorch.org/whl/cpu && \
    pip --no-cache-dir install -r requirements.txt --user && \
    apt-get update && \
    apt-get install -y amqp-tools && \
    rm -rf /var/lib/apt/lists/*

# download models
RUN python /app/src/app.py --prompt "dog" && rm /app/results/*

CMD ["/app/consumer.sh"]
