## Stable Diffusion - WebUI

This is a [Next.js](https://nextjs.org/) project that's deployed at [ai.example.kedify.io](http://ai.example.kedify.io/).

## Getting Started

First, run the development server:

```bash
AMQP_URL=foo npm run dev
```
or if you have the access to the k8s cluster where it's deployed

```bash
cd .. && make run-webui-dev
```

Open [http://localhost:3000](http://localhost:3000).

## Architecture

### Displaying Images

The application renders images from `public/images` directory and present them as a image gallery in a grid format.
It sorts them by date and displays only the N latest ones (N=24 atm).
Application also shows metadata about the AI model that generated the image from a JSON file.
This needs to be called the same was as the image and should be stored in the same directory (`public/images`).

This application is designed to be run in Kubernetes with a side-car container that makes sure the images are copied to the app's filesystem.
We do that by using Minio shared storage.
For more details check [webapp.yaml](https://github.com/kedify/examples/blob/803c28a19eb6c1b6b7a625bb9932c0566a762778/samples/stable-diffusion/manifests/webapp.yaml#L62-L88).

### Generating Images

App can [send](https://github.com/kedify/examples/blob/803c28a19eb6c1b6b7a625bb9932c0566a762778/samples/stable-diffusion/webui/app/services/images.ts#L36) 
a messages to a RabbitMQ queue called `tasks` using the AMQP protocol. It needs the `AMQP_URL` environment variable to be configured properly.

Example:

```bash
export AMQP_URL=amqp://username:password@rabbitmq-cluster.rabbitmq-system.svc.cluster.local:5672
```

Once the message is delivered to the job queue, KEDA spins new worker pods that consume the messages one by one and trigger the trained stable diffusion neural network in feed-forward mode to create the image.

Message format:
```json
{
  "prompt": "green dog",
  "count": 2
}
```

This message represents one job on worker that will create two images of a 'green dog'. The count is mapped from the slider component.

Metadata format:
```json
{
    "lcm_model_id": "stabilityai/sd-turbo",
    "openvino_lcm_model_id": "rupeshs/sd-turbo-openvino",
    "use_offline_model": false,
    "use_lcm_lora": false,
    "lcm_lora": {
        "base_model_id": "Lykon/dreamshaper-8",
        "lcm_lora_id": "latent-consistency/lcm-lora-sdv1-5"
    },
    "use_tiny_auto_encoder": false,
    "use_openvino": false,
    "prompt": "Golden Gate",
    "negative_prompt": "",
    "strength": 0.3,
    "image_height": 512,
    "image_width": 512,
    "inference_steps": 1,
    "guidance_scale": 1.0,
    "number_of_images": 4,
    "seed": -1,
    "use_seed": false,
    "use_safety_checker": false,
    "diffusion_task": "text_to_image",
    "lora": {
        "weight": 0.5,
        "fuse": true,
        "enabled": false
    },
    "controlnet": null,
    "rebuild_pipeline": false
}
```
