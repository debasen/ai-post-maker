import fs from 'fs/promises';
import path from 'path';
import { config } from '../config.js';

/**
 * Ensure temp directory exists
 */
export async function ensureTempDir(): Promise<void> {
  try {
    await fs.access(config.temp.dir);
  } catch {
    await fs.mkdir(config.temp.dir, { recursive: true });
  }
}

/**
 * Save file to temp directory
 */
export async function saveTempFile(
  filename: string,
  data: Buffer | string
): Promise<string> {
  await ensureTempDir();
  const filePath = path.join(config.temp.dir, filename);
  await fs.writeFile(filePath, data);
  return filePath;
}

/**
 * Download file from URL and save to temp directory
 */
export async function downloadToTemp(
  url: string,
  filename: string
): Promise<string> {
  const axios = (await import('axios')).default;
  const response = await axios.get(url, { responseType: 'arraybuffer' });
  return saveTempFile(filename, Buffer.from(response.data));
}

/**
 * Clean up temp file
 */
export async function cleanupTempFile(filePath: string): Promise<void> {
  try {
    await fs.unlink(filePath);
  } catch (error) {
    console.warn(`Failed to cleanup temp file ${filePath}:`, error);
  }
}

/**
 * Get file extension from URL or filename
 */
export function getFileExtension(urlOrFilename: string): string {
  const match = urlOrFilename.match(/\.([^.]+)(?:\?|$)/);
  return match ? match[1] : 'bin';
}

/**
 * Generate unique filename with extension
 */
export function generateTempFilename(prefix: string, extension: string): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return `${prefix}_${timestamp}_${random}.${extension}`;
}

