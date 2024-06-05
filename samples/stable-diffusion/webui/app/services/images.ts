'use server';

import { promises as fs } from 'fs';
import amqplib from 'amqplib';
import { GeneratedImage, JobRequest } from '../types';

export async function getAvailableImages(): Promise<GeneratedImage[]> {
  const cwd = process.cwd();
  const imageLimit = 24; // 2*12, 3*8, 4*6 .. grid
  const images = (await fs.readdir(`${cwd}/public/generated`))
    .filter(path => path.endsWith('.png'))
    .map(async (path, index) => {
      const name = path.slice(0, path.lastIndexOf('-'));
      const metadataFile = await fs.readFile(`${cwd}/public/generated/${name}.json`, 'utf8');
      const metadata = JSON.parse(metadataFile);
      const model: string = metadata ? metadata['lcm_model_id'] : 'unknown';
      const prompt: string = metadata ? metadata['prompt'].replace(/['"]+/g, '') : 'unknown';
      const loraModel: string = metadata ? metadata['lcm_lora'] ? metadata['lcm_lora']['base_model_id'] : 'unknown' : 'unknown';
      const width = metadata ? metadata['image_width'] : 512;
      const height = metadata ? metadata['image_height'] : 512;
      const generatedDate = (await fs.lstat(`${cwd}/public/generated/${path}`)).ctime
      return {
        id: index,
        height: +height,
        width: +width,
        url: '/generated/' + path,
        prompt: prompt,
        model: model,
        loraModel: loraModel,
        generatedDate: generatedDate,
      } satisfies GeneratedImage
    });
  return (await Promise.all(images)).toSorted((a, b) => +b.generatedDate - +a.generatedDate).slice(0, imageLimit)
}

export async function sendToQueue(prompt: string, inParallel = false, count = 1) {
  const queue = 'tasks';
  console.log(`sending request for ${count} '${prompt}' to ${queue} ${inParallel && count > 1 ? 'in parallel': 'sequentially'}`)
  const conn = await amqplib.connect(`${process.env.AMQP_URL}`);
  const channel = await conn.createChannel();

  // asserts the queue exists
  channel.assertQueue(queue, {
    durable: false,
  });
  if (inParallel && count > 1) {
    for (let i = 0; i < count; i++) {
      channel.sendToQueue(queue, Buffer.from(JSON.stringify({
        prompt: prompt,
        count: 1,
      } satisfies JobRequest)));
    }
  } else {
    channel.sendToQueue(queue, Buffer.from(JSON.stringify({
      prompt: prompt,
      count: count,
    } satisfies JobRequest)));
  }
}
