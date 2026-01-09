/**
 * Generate prompt for recipe text generation
 */
export function generateRecipePrompt(foodName: string): string {
  return `
Create a detailed, authentic recipe for ${foodName}.
Include:
- Prep time and cook time
- Serving size
- Complete ingredient list with measurements
- Step-by-step instructions
- Pro tips for best results
- Calorie estimate

Style: Warm, encouraging, like a friend sharing their secret recipe.
Keep it concise but complete (under 500 words for description).
`.trim();
}

/**
 * Generate recipe prompt with specific format requirements
 */
export function generateFormattedRecipePrompt(
  foodName: string,
  format: 'markdown' | 'plain' | 'social' = 'social'
): string {
  const basePrompt = generateRecipePrompt(foodName);

  const formatInstructions = {
    markdown: `
Format the recipe in Markdown with:
- ## Title
- **Prep Time:** X minutes
- **Cook Time:** X minutes
- **Servings:** X
- **Calories:** ~X per serving

### Ingredients
- List format

### Instructions
1. Numbered steps

### Pro Tips
- Bullet points
`.trim(),

    plain: `
Format the recipe as plain text with clear sections.
`.trim(),

    social: `
Format the recipe optimized for social media:
- Start with an engaging hook
- Use emojis sparingly (food-related only)
- Include hashtags at the end
- Keep paragraphs short and scannable
- Make it shareable and engaging
`.trim(),
  };

  return `${basePrompt}\n\n${formatInstructions[format]}`;
}

