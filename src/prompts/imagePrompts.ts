/**
 * Generate prompt for realistic food image generation
 */
export function generateFoodImagePrompt(foodName: string): string {
  return `
Professional food photography of ${foodName}.
Style: Editorial magazine quality, Michelin-star presentation
Lighting: Warm, natural daylight from side
Composition: Close-up, shallow depth of field
Props: Minimal, elegant table setting
Mood: Inviting, appetizing, makes viewer hungry
IMPORTANT: Hyper-realistic, NOT illustrated or AI-looking
Aspect ratio: 9:16 vertical (portrait for Reels)
`.trim();
}

/**
 * Generate alternative prompt variations for A/B testing
 */
export function generateFoodImagePromptVariation(
  foodName: string,
  variation: 'dramatic' | 'minimal' | 'rustic' | 'elegant' = 'elegant'
): string {
  const variations = {
    dramatic: `
Dramatic food photography of ${foodName}.
Style: High contrast, bold colors, cinematic lighting
Lighting: Dramatic shadows and highlights, moody atmosphere
Composition: Dynamic angles, dramatic perspective
Props: Dark background, spotlight effect
Mood: Intense, captivating, makes viewer crave
IMPORTANT: Hyper-realistic, NOT illustrated or AI-looking
Aspect ratio: 9:16 vertical (portrait for Reels)
`.trim(),

    minimal: `
Minimalist food photography of ${foodName}.
Style: Clean, simple, modern aesthetic
Lighting: Soft, even, natural light
Composition: Centered, lots of negative space
Props: White or neutral background, minimal props
Mood: Clean, fresh, appetizing
IMPORTANT: Hyper-realistic, NOT illustrated or AI-looking
Aspect ratio: 9:16 vertical (portrait for Reels)
`.trim(),

    rustic: `
Rustic food photography of ${foodName}.
Style: Homestyle, cozy, authentic
Lighting: Warm, golden hour lighting
Composition: Casual, inviting arrangement
Props: Wooden boards, linen, natural textures
Mood: Comforting, homey, makes viewer feel welcome
IMPORTANT: Hyper-realistic, NOT illustrated or AI-looking
Aspect ratio: 9:16 vertical (portrait for Reels)
`.trim(),

    elegant: `
Elegant food photography of ${foodName}.
Style: Fine dining presentation, sophisticated
Lighting: Warm, natural daylight from side
Composition: Close-up, shallow depth of field
Props: Minimal, elegant table setting
Mood: Inviting, appetizing, makes viewer hungry
IMPORTANT: Hyper-realistic, NOT illustrated or AI-looking
Aspect ratio: 9:16 vertical (portrait for Reels)
`.trim(),
  };

  return variations[variation];
}

