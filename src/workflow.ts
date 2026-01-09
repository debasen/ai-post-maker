import { selectUniqueFoodItem } from './utils/foodSelector.js';
import { generateFoodImage } from './services/monica/image.js';
import { animateImage } from './services/monica/video.js';
import { generateRecipe } from './services/monica/chat.js';
import { facebookService } from './services/facebook.js';
import { recipeTracker } from './database/recipes.js';

export interface WorkflowResult {
  success: boolean;
  foodName: string;
  category: string;
  imageUrl?: string;
  videoUrl?: string;
  recipeText?: string;
  fbPostId?: string;
  error?: string;
}

/**
 * Main workflow: Generate food video and post to Facebook Reels
 */
export async function generateAndPostFoodReel(): Promise<WorkflowResult> {
  const result: WorkflowResult = {
    success: false,
    foodName: '',
    category: '',
  };

  try {
    console.log('🍽️  Starting food video workflow...');

    // Step 1: Select unique food item
    console.log('📋 Selecting food item...');
    const foodItem = selectUniqueFoodItem();
    result.foodName = foodItem.name;
    result.category = foodItem.category;
    console.log(`✅ Selected: ${foodItem.name} (${foodItem.category})`);

    // Step 2: Generate food image
    console.log('🎨 Generating food image...');
    const imageResult = await generateFoodImage(foodItem.name);
    result.imageUrl = imageResult.imageUrl;
    console.log(`✅ Image generated: ${imageResult.imageUrl}`);

    // Step 3: Animate image to video
    console.log('🎬 Animating image to video...');
    const videoResult = await animateImage({
      imageUrl: imageResult.imageUrl,
      imagePath: imageResult.localPath,
      duration: 8,
      motion: 'moderate',
    });
    result.videoUrl = videoResult.videoUrl;
    console.log(`✅ Video generated: ${videoResult.videoUrl}`);

    // Step 4: Generate recipe
    console.log('📝 Generating recipe...');
    const recipe = await generateRecipe(foodItem.name, 'social');
    result.recipeText = recipe.fullText;
    console.log(`✅ Recipe generated`);

    // Step 5: Post to Facebook Reels
    console.log('📤 Posting to Facebook Reels...');
    const hashtags = facebookService.generateHashtags(
      foodItem.name,
      foodItem.category
    );

    const fbResult = await facebookService.postReel({
      videoPath: videoResult.localPath,
      title: `Delicious ${foodItem.name} Recipe 🍽️`,
      description: recipe.fullText,
      hashtags,
    });
    result.fbPostId = fbResult.postId;
    console.log(`✅ Posted to Facebook: ${fbResult.postId}`);

    // Step 6: Record in database
    console.log('💾 Recording in database...');
    recipeTracker.recordPostedRecipe(
      foodItem.name,
      foodItem.category,
      imageResult.imageUrl,
      videoResult.videoUrl,
      fbResult.postId,
      recipe.fullText
    );
    console.log('✅ Recorded in database');

    result.success = true;
    console.log('🎉 Workflow completed successfully!');
    return result;
  } catch (error) {
    console.error('❌ Workflow failed:', error);
    result.error =
      error instanceof Error ? error.message : 'Unknown error occurred';
    result.success = false;
    return result;
  }
}

/**
 * Test workflow without posting (dry run)
 */
export async function testWorkflow(): Promise<WorkflowResult> {
  const result: WorkflowResult = {
    success: false,
    foodName: '',
    category: '',
  };

  try {
    console.log('🧪 Testing workflow (dry run)...');

    // Step 1: Select unique food item
    const foodItem = selectUniqueFoodItem();
    result.foodName = foodItem.name;
    result.category = foodItem.category;
    console.log(`✅ Selected: ${foodItem.name}`);

    // Step 2: Generate food image
    const imageResult = await generateFoodImage(foodItem.name);
    result.imageUrl = imageResult.imageUrl;
    console.log(`✅ Image generated`);

    // Step 3: Animate image to video
    const videoResult = await animateImage({
      imageUrl: imageResult.imageUrl,
      imagePath: imageResult.localPath,
      duration: 8,
      motion: 'moderate',
    });
    result.videoUrl = videoResult.videoUrl;
    console.log(`✅ Video generated`);

    // Step 4: Generate recipe
    const recipe = await generateRecipe(foodItem.name, 'social');
    result.recipeText = recipe.fullText;
    console.log(`✅ Recipe generated`);

    // Skip Facebook posting for test
    console.log('⏭️  Skipping Facebook post (test mode)');

    result.success = true;
    return result;
  } catch (error) {
    console.error('❌ Test workflow failed:', error);
    result.error =
      error instanceof Error ? error.message : 'Unknown error occurred';
    result.success = false;
    return result;
  }
}

