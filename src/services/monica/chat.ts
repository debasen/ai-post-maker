import { monicaClient, MODELS } from './client.js';
import { generateFormattedRecipePrompt } from '../../prompts/recipePrompts.js';

export interface Recipe {
  title: string;
  prepTime: string;
  cookTime: string;
  servings: string;
  calories?: string;
  ingredients: string[];
  instructions: string[];
  proTips: string[];
  fullText: string; // Complete formatted recipe text
}

/**
 * Generate a detailed recipe using GPT-4.1 via Monica API
 */
export async function generateRecipe(
  foodName: string,
  format: 'markdown' | 'plain' | 'social' = 'social'
): Promise<Recipe> {
  const prompt = generateFormattedRecipePrompt(foodName, format);

  try {
    const response = await monicaClient.chat.completions.create({
      model: MODELS.CHAT,
      messages: [
        {
          role: 'user',
          content: prompt,
        },
      ],
      temperature: 0.7,
      max_tokens: 1000,
    });

    const recipeText =
      response.choices[0]?.message?.content ||
      'Recipe generation failed. Please try again.';

    // Parse recipe text to extract structured data
    const parsedRecipe = parseRecipeText(recipeText, foodName);

    return {
      ...parsedRecipe,
      fullText: recipeText,
    };
  } catch (error) {
    console.error('Error generating recipe:', error);
    throw new Error(
      `Failed to generate recipe: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

/**
 * Parse recipe text to extract structured information
 */
function parseRecipeText(text: string, foodName: string): Omit<Recipe, 'fullText'> {
  // Default values
  const recipe: Omit<Recipe, 'fullText'> = {
    title: foodName,
    prepTime: '15 minutes',
    cookTime: '30 minutes',
    servings: '4',
    ingredients: [],
    instructions: [],
    proTips: [],
  };

  // Try to extract prep time
  const prepTimeMatch = text.match(/prep.*?time[:\s]+(\d+[\s\w]+)/i);
  if (prepTimeMatch) {
    recipe.prepTime = prepTimeMatch[1];
  }

  // Try to extract cook time
  const cookTimeMatch = text.match(/cook.*?time[:\s]+(\d+[\s\w]+)/i);
  if (cookTimeMatch) {
    recipe.cookTime = cookTimeMatch[1];
  }

  // Try to extract servings
  const servingsMatch = text.match(/servings?[:\s]+(\d+)/i);
  if (servingsMatch) {
    recipe.servings = servingsMatch[1];
  }

  // Try to extract calories
  const caloriesMatch = text.match(/calories?[:\s]+(~?[\d,]+)/i);
  if (caloriesMatch) {
    recipe.calories = caloriesMatch[1];
  }

  // Extract ingredients (look for bullet points or numbered lists)
  const ingredientsSection = text.match(/ingredients?[:\s]*\n([\s\S]*?)(?=\n\n|instructions?|steps?|directions?)/i);
  if (ingredientsSection) {
    const ingredientLines = ingredientsSection[1]
      .split('\n')
      .map((line) => line.replace(/^[-•*]\s*|\d+\.\s*/, '').trim())
      .filter((line) => line.length > 0);
    recipe.ingredients = ingredientLines;
  }

  // Extract instructions
  const instructionsSection = text.match(/(?:instructions?|steps?|directions?)[:\s]*\n([\s\S]*?)(?=\n\n(?:tips?|pro|notes?)|$)/i);
  if (instructionsSection) {
    const instructionLines = instructionsSection[1]
      .split('\n')
      .map((line) => line.replace(/^\d+\.\s*/, '').trim())
      .filter((line) => line.length > 0);
    recipe.instructions = instructionLines;
  }

  // Extract pro tips
  const tipsSection = text.match(/(?:tips?|pro\s+tips?)[:\s]*\n([\s\S]*?)$/i);
  if (tipsSection) {
    const tipLines = tipsSection[1]
      .split('\n')
      .map((line) => line.replace(/^[-•*]\s*/, '').trim())
      .filter((line) => line.length > 0);
    recipe.proTips = tipLines;
  }

  return recipe;
}

/**
 * Generate recipe text optimized for social media captions
 */
export async function generateSocialMediaRecipe(
  foodName: string
): Promise<string> {
  const recipe = await generateRecipe(foodName, 'social');
  return recipe.fullText;
}

