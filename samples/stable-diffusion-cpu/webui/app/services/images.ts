'use server';

import { promises as fs } from 'fs';
import amqplib from 'amqplib';

export async function getAvailableImages(): Promise<string[]> {
  const cwd = process.cwd();
  const images = await fs.readdir(`${cwd}/public/generated`)
  return images
}


export async function sendToQueue(img: string) {
  const queue = 'tasks';
  const conn = await amqplib.connect(`${process.env.AMQP_URL}`);
  const channel = await conn.createChannel();

  // asserts the queue exists
  channel.assertQueue(queue);
  channel.sendToQueue(queue, Buffer.from(img));
}
