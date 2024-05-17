'use server';

import { promises as fs } from 'fs';

export async function getAvailableImages(): Promise<string[]> {
  const cwd = process.cwd();
  const images = await fs.readdir(`${cwd}/public/generated`)
  return images
}
