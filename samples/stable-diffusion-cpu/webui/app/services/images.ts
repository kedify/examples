'use server';

import { promises as fs } from 'fs';
import amqplib from 'amqplib';

export async function getAvailableImages(): Promise<string[]> {
  console.log(process.cwd());
  const cwd = process.cwd();
  const images = (await fs.readdir(`${cwd}/public/generated`)).filter((path) => path.endsWith('png'));
  return images
}


export async function sendToQueue(img: string) {
  const queue = 'tasks';
  console.log(`sending ${img} to ${queue}`)
  const conn = await amqplib.connect(`${process.env.AMQP_URL}`);
  const channel = await conn.createChannel();

  // asserts the queue exists
  channel.assertQueue(queue, {
    durable: false,
  });
  channel.sendToQueue(queue, Buffer.from(img));
}
