import { monicaClient, MODELS } from './client.js';
import { generateFoodImagePrompt } from '../../prompts/imagePrompts.js';
import { downloadToTemp, generateTempFilename, getFileExtension } from '../../utils/fileManager.js';

export interface ImageGenerationResult {
  imageUrl: string;
  localPath: string;
}

/**
 * Generate a realistic food image using Nano Banana Pro via Monica API
 */
export async function generateFoodImage(
  foodName: string
): Promise<ImageGenerationResult> {
  const prompt = generateFoodImagePrompt(foodName);

  try {
    // Generate image using Monica API
    const response = await monicaClient.images.generate({
      model: MODELS.IMAGE,
      prompt: prompt,
      n: 1,
      size: '1024x1792', // 9:16 aspect ratio for Reels
    });

    const imageUrl = response.data[0]?.url;
    if (!imageUrl) {
      throw new Error('No image URL returned from Monica API');
    }

    // Download image to temp directory
    const extension = getFileExtension(imageUrl);
    const filename = generateTempFilename('food_image', extension);
    const localPath = await downloadToTemp(imageUrl, filename);

    return {
      imageUrl,
      localPath,
    };
  } catch (error) {
    console.error('Error generating food image:', error);
    throw new Error(
      `Failed to generate food image: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

/**
 * Generate multiple image variations (for future multi-angle feature)
 */
export async function generateFoodImageVariations(
  foodName: string,
  count: number = 1
): Promise<ImageGenerationResult[]> {
  const results: ImageGenerationResult[] = [];

  for (let i = 0; i < count; i++) {
    const result = await generateFoodImage(foodName);
    results.push(result);
    // Small delay between requests to avoid rate limits
    if (i < count - 1) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  return results;
}

