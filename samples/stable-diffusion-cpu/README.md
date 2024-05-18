## Stable Diffusion use-case

todo: diagram
https://excalidraw.com/#json=YIHErhV8tspabLzG6tsRs,Ln9kTX9SDdsy2FUfd_05Uw

### try the container image locally

```
make build-image
PROMPT="cartoon dwarf" NUM_IMAGES=7 make run-example
```

### Deploy to K8s

```
make deploy
```

This deploys one replica of web ui, Minio, RabbitMQ and one replica of worker deployment that can generate the images.

## Common Pain Points

### Container images are too large

Reasons:
- the models are too large (~4 gigs)
- python

Mitigations:
- pre-fetch or even bake the container images on a newly spawned k8s nodes

### GPUs being too expensive
- https://cloud.google.com/spot-vms/pricing#gpu_pricing
