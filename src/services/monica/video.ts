import { MODELS } from './client.js';
import { downloadToTemp, generateTempFilename, getFileExtension } from '../../utils/fileManager.js';
import axios from 'axios';

export interface VideoGenerationOptions {
  imageUrl: string;
  imagePath?: string; // Local file path if available
  duration?: number; // 5-10 seconds for Reels
  motion?: 'subtle' | 'moderate' | 'dynamic';
}

export interface VideoGenerationResult {
  videoUrl: string;
  localPath: string;
}

/**
 * Animate an image to video using Kling AI via Monica API
 * Note: Monica API may use different endpoints for video generation
 * This implementation follows OpenAI-compatible patterns but may need adjustment
 */
export async function animateImage(
  options: VideoGenerationOptions
): Promise<VideoGenerationResult> {
  const {
    imageUrl,
    imagePath,
    duration = 8, // Default 8 seconds
    motion = 'moderate',
  } = options;

  try {
    // Monica API video generation - try direct API call first
    // Note: Actual endpoint may vary based on Monica API documentation
    return await generateVideoFallback(options);
  } catch (error) {
    console.error('Error generating video:', error);
    throw error;
  }
}

/**
 * Video generation using Monica API
 * Note: This implementation may need adjustment based on actual Monica API documentation
 * Monica API might use different endpoints or formats for video generation
 */
async function generateVideoFallback(
  options: VideoGenerationOptions
): Promise<VideoGenerationResult> {
  const { config } = await import('../../config.js');

  try {
    // Try direct API call - Monica API may have a specific video endpoint
    // Adjust endpoint and payload structure based on actual API docs
    const response = await axios.post(
      `${config.monica.baseURL}/video/generate`,
      {
        model: MODELS.VIDEO,
        image_url: options.imageUrl,
        duration: options.duration || 8,
        motion: options.motion || 'moderate',
      },
      {
        headers: {
          Authorization: `Bearer ${config.monica.apiKey}`,
          'Content-Type': 'application/json',
        },
      }
    );

    // Extract video URL from response
    // Response structure may vary - adjust based on actual API response
    const videoUrl =
      response.data?.video_url ||
      response.data?.url ||
      response.data?.data?.video_url ||
      response.data?.data?.url;

    if (!videoUrl) {
      console.error('API Response:', JSON.stringify(response.data, null, 2));
      throw new Error('No video URL in response');
    }

    // Download video to temp directory
    const extension = getFileExtension(videoUrl) || 'mp4';
    const filename = generateTempFilename('food_video', extension);
    const localPath = await downloadToTemp(videoUrl, filename);

    return {
      videoUrl,
      localPath,
    };
  } catch (error: any) {
    // If the endpoint doesn't exist, try alternative approach
    if (error.response?.status === 404) {
      console.warn(
        'Video endpoint not found. Monica API may use a different endpoint structure.'
      );
      console.warn(
        'Please check Monica API documentation for the correct video generation endpoint.'
      );
    }
    throw new Error(
      `Failed to generate video: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

