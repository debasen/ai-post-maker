import Database from 'better-sqlite3';
import { config } from '../config.js';
import path from 'path';
import fs from 'fs';

// Ensure data directory exists
const dataDir = path.dirname(config.database.path);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

export const db = new Database(config.database.path);

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS posted_recipes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    food_name TEXT NOT NULL,
    category TEXT NOT NULL,
    posted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    image_url TEXT,
    video_url TEXT,
    fb_post_id TEXT,
    recipe_text TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_posted_at ON posted_recipes(posted_at);
  CREATE INDEX IF NOT EXISTS idx_food_name ON posted_recipes(food_name);
  CREATE INDEX IF NOT EXISTS idx_category ON posted_recipes(category);
`);

export interface PostedRecipe {
  id: number;
  food_name: string;
  category: string;
  posted_at: string;
  image_url: string | null;
  video_url: string | null;
  fb_post_id: string | null;
  recipe_text: string | null;
  created_at: string;
}

