import axios, { AxiosInstance } from 'axios';
import FormData from 'form-data';
import fs from 'fs';
import { config } from '../config.js';
import { cleanupTempFile } from '../utils/fileManager.js';

export interface FacebookReelPost {
  videoPath: string;
  title: string;
  description: string;
  hashtags?: string[];
}

export interface FacebookPostResult {
  postId: string;
  permalink?: string;
}

/**
 * Facebook Graph API service for posting Reels
 */
export class FacebookService {
  private api: AxiosInstance;
  private pageId: string;
  private accessToken: string;

  constructor() {
    this.pageId = config.facebook.pageId;
    this.accessToken = config.facebook.pageAccessToken;

    this.api = axios.create({
      baseURL: 'https://graph.facebook.com/v21.0',
      params: {
        access_token: this.accessToken,
      },
    });
  }

  /**
   * Upload video to Facebook and create a Reel post
   */
  async postReel(post: FacebookReelPost): Promise<FacebookPostResult> {
    try {
      // Step 1: Upload video file
      const videoId = await this.uploadVideo(post.videoPath);

      // Step 2: Wait for video processing (Facebook needs time to process)
      await this.waitForVideoProcessing(videoId);

      // Step 3: Create Reel post with video
      const reelId = await this.createReel(videoId, post);

      // Step 4: Cleanup temp file
      await cleanupTempFile(post.videoPath);

      return {
        postId: reelId,
      };
    } catch (error) {
      console.error('Error posting reel to Facebook:', error);
      throw new Error(
        `Failed to post reel: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  /**
   * Upload video file to Facebook
   */
  private async uploadVideo(videoPath: string): Promise<string> {
    const formData = new FormData();
    formData.append('source', fs.createReadStream(videoPath));
    formData.append('description', 'Food video reel');

    try {
      const response = await this.api.post(
        `/${this.pageId}/videos`,
        formData,
        {
          headers: {
            ...formData.getHeaders(),
          },
          maxContentLength: Infinity,
          maxBodyLength: Infinity,
        }
      );

      const videoId = response.data.id;
      if (!videoId) {
        throw new Error('No video ID returned from Facebook API');
      }

      return videoId;
    } catch (error: any) {
      if (error.response) {
        throw new Error(
          `Facebook API error: ${JSON.stringify(error.response.data)}`
        );
      }
      throw error;
    }
  }

  /**
   * Wait for video to be processed by Facebook
   */
  private async waitForVideoProcessing(
    videoId: string,
    maxWaitTime: number = 300000
  ): Promise<void> {
    const startTime = Date.now();
    const checkInterval = 5000; // Check every 5 seconds

    while (Date.now() - startTime < maxWaitTime) {
      try {
        const response = await this.api.get(`/${videoId}`, {
          params: {
            fields: 'status',
          },
        });

        const status = response.data.status;
        if (status === 'ready' || status === 'published') {
          return;
        }

        // Wait before next check
        await new Promise((resolve) => setTimeout(resolve, checkInterval));
      } catch (error) {
        console.warn('Error checking video status:', error);
        // Continue waiting
        await new Promise((resolve) => setTimeout(resolve, checkInterval));
      }
    }

    // If we've waited too long, proceed anyway (video might still process)
    console.warn(
      `Video ${videoId} processing timeout. Proceeding with post creation.`
    );
  }

  /**
   * Create Reel post with video ID
   */
  private async createReel(
    videoId: string,
    post: FacebookReelPost
  ): Promise<string> {
    // Format description with hashtags
    let description = post.description;
    if (post.hashtags && post.hashtags.length > 0) {
      const hashtagsText = post.hashtags
        .map((tag) => (tag.startsWith('#') ? tag : `#${tag}`))
        .join(' ');
      description = `${description}\n\n${hashtagsText}`;
    }

    // Add note about music (since we can't add it programmatically)
    description = `${description}\n\n🎵 Add trending music to make this reel pop!`;

    try {
      const response = await this.api.post(`/${this.pageId}/reels`, {
        video_id: videoId,
        title: post.title,
        description: description,
        content_category: 'FOOD',
      });

      const reelId = response.data.id;
      if (!reelId) {
        throw new Error('No reel ID returned from Facebook API');
      }

      return reelId;
    } catch (error: any) {
      if (error.response) {
        throw new Error(
          `Facebook API error: ${JSON.stringify(error.response.data)}`
        );
      }
      throw error;
    }
  }

  /**
   * Generate relevant hashtags for food content
   */
  generateHashtags(foodName: string, category: string): string[] {
    const baseHashtags = [
      'food',
      'foodie',
      'recipe',
      'cooking',
      'delicious',
      'foodporn',
      'homemade',
      'foodlover',
    ];

    const categoryHashtags: Record<string, string[]> = {
      Italian: ['italianfood', 'italiancuisine', 'pasta'],
      Asian: ['asianfood', 'asiancuisine'],
      American: ['americanfood', 'comfortfood'],
      Mexican: ['mexicanfood', 'mexicancuisine', 'tacos'],
      Mediterranean: ['mediterraneanfood', 'healthyfood'],
      Dessert: ['dessert', 'sweet', 'baking'],
      Breakfast: ['breakfast', 'brunch', 'morning'],
      Seafood: ['seafood', 'fish', 'fresh'],
      Vegetarian: ['vegetarian', 'veggie', 'plantbased'],
      Soup: ['soup', 'comfortfood'],
      Sandwich: ['sandwich', 'lunch'],
      Grilled: ['grilled', 'bbq', 'bbqfood'],
    };

    const categoryTags = categoryHashtags[category] || [];
    const foodNameTag = foodName.toLowerCase().replace(/\s+/g, '');

    return [
      ...baseHashtags,
      ...categoryTags,
      foodNameTag,
      category.toLowerCase(),
    ].slice(0, 15); // Limit to 15 hashtags
  }
}

export const facebookService = new FacebookService();

