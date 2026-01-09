import OpenAI from 'openai';
import { config } from '../../config.js';

export const monicaClient = new OpenAI({
  apiKey: config.monica.apiKey,
  baseURL: config.monica.baseURL,
});

// Available models for our workflow
export const MODELS = {
  IMAGE: 'nano-banana-pro', // Realistic food image generation
  VIDEO: 'kling-ai', // Image-to-video animation
  CHAT: 'gpt-4.1', // Recipe text generation
} as const;

// Alternative models available via Monica
export const ALTERNATIVE_MODELS = {
  IMAGE: [
    'flux-pro',
    'flux-schnell',
    'dall-e-3',
    'stable-diffusion-xl',
    'ideogram-v2',
  ],
  VIDEO: ['runway-gen3', 'pika-ai', 'hailuo-ai', 'stable-video-diffusion'],
  CHAT: [
    'claude-opus-4',
    'claude-sonnet-4',
    'gemini-2.5-pro',
    'gpt-4o',
    'gpt-4-turbo',
  ],
} as const;

