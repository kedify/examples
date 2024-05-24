export interface GeneratedImage {
  id: number;
  height: number;
  width: number;
  url: string;
  prompt: string;
  model: string;
  loraModel: string;
  generatedDate: Date;
  // blurDataUrl?: string;
}

export interface JobRequest {
  prompt: string;
  count: number;
}
