import { db, PostedRecipe } from './db.js';

export class RecipeTracker {
  /**
   * Check if a food item was posted recently (within specified days)
   */
  wasPostedRecently(foodName: string, days: number = 30): boolean {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    const result = db
      .prepare(
        `
      SELECT COUNT(*) as count
      FROM posted_recipes
      WHERE food_name = ? AND posted_at > ?
    `
      )
      .get(foodName, cutoffDate.toISOString()) as { count: number };

    return result.count > 0;
  }

  /**
   * Get all posted recipes within a date range
   */
  getPostedRecipes(days: number = 30): PostedRecipe[] {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    return db
      .prepare(
        `
      SELECT *
      FROM posted_recipes
      WHERE posted_at > ?
      ORDER BY posted_at DESC
    `
      )
      .all(cutoffDate.toISOString()) as PostedRecipe[];
  }

  /**
   * Record a posted recipe
   */
  recordPostedRecipe(
    foodName: string,
    category: string,
    imageUrl: string | null,
    videoUrl: string | null,
    fbPostId: string | null,
    recipeText: string | null
  ): number {
    const result = db
      .prepare(
        `
      INSERT INTO posted_recipes 
        (food_name, category, image_url, video_url, fb_post_id, recipe_text)
      VALUES (?, ?, ?, ?, ?, ?)
    `
      )
      .run(foodName, category, imageUrl, videoUrl, fbPostId, recipeText);

    return result.lastInsertRowid as number;
  }

  /**
   * Get all unique food names that have been posted
   */
  getAllPostedFoodNames(): string[] {
    const results = db
      .prepare(`SELECT DISTINCT food_name FROM posted_recipes`)
      .all() as { food_name: string }[];

    return results.map((r) => r.food_name);
  }

  /**
   * Get count of recipes posted in a category
   */
  getCategoryCount(category: string, days: number = 30): number {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    const result = db
      .prepare(
        `
      SELECT COUNT(*) as count
      FROM posted_recipes
      WHERE category = ? AND posted_at > ?
    `
      )
      .get(category, cutoffDate.toISOString()) as { count: number };

    return result.count;
  }
}

export const recipeTracker = new RecipeTracker();

