import { recipeTracker } from '../database/recipes.js';

export interface FoodItem {
  name: string;
  category: string;
  trending: boolean; // Weight factor for viral/trending foods
}

// Curated list of 200+ appealing food items
const FOOD_ITEMS: FoodItem[] = [
  // Italian
  { name: 'Margherita Pizza', category: 'Italian', trending: true },
  { name: 'Spaghetti Carbonara', category: 'Italian', trending: true },
  { name: 'Lasagna', category: 'Italian', trending: false },
  { name: 'Risotto', category: 'Italian', trending: true },
  { name: 'Tiramisu', category: 'Italian', trending: true },
  { name: 'Penne Arrabbiata', category: 'Italian', trending: false },
  { name: 'Fettuccine Alfredo', category: 'Italian', trending: true },
  { name: 'Chicken Parmesan', category: 'Italian', trending: true },
  { name: 'Caprese Salad', category: 'Italian', trending: false },
  { name: 'Osso Buco', category: 'Italian', trending: false },

  // Asian
  { name: 'Pad Thai', category: 'Asian', trending: true },
  { name: 'Ramen', category: 'Asian', trending: true },
  { name: 'Sushi Platter', category: 'Asian', trending: true },
  { name: 'Korean BBQ', category: 'Asian', trending: true },
  { name: 'Chicken Tikka Masala', category: 'Asian', trending: true },
  { name: 'Beef Bulgogi', category: 'Asian', trending: true },
  { name: 'Pho', category: 'Asian', trending: true },
  { name: 'General Tso Chicken', category: 'Asian', trending: false },
  { name: 'Bibimbap', category: 'Asian', trending: true },
  { name: 'Dumplings', category: 'Asian', trending: true },
  { name: 'Teriyaki Salmon', category: 'Asian', trending: true },
  { name: 'Miso Soup', category: 'Asian', trending: false },
  { name: 'Chicken Katsu', category: 'Asian', trending: true },
  { name: 'Mapo Tofu', category: 'Asian', trending: false },
  { name: 'Tom Yum Soup', category: 'Asian', trending: true },

  // American
  { name: 'Classic Burger', category: 'American', trending: true },
  { name: 'BBQ Ribs', category: 'American', trending: true },
  { name: 'Mac and Cheese', category: 'American', trending: true },
  { name: 'Fried Chicken', category: 'American', trending: true },
  { name: 'Pulled Pork Sandwich', category: 'American', trending: true },
  { name: 'Buffalo Wings', category: 'American', trending: true },
  { name: 'Caesar Salad', category: 'American', trending: false },
  { name: 'Chicken Tenders', category: 'American', trending: true },
  { name: 'Grilled Cheese', category: 'American', trending: true },
  { name: 'Chili', category: 'American', trending: false },

  // Mexican
  { name: 'Tacos', category: 'Mexican', trending: true },
  { name: 'Burrito Bowl', category: 'Mexican', trending: true },
  { name: 'Quesadilla', category: 'Mexican', trending: true },
  { name: 'Enchiladas', category: 'Mexican', trending: false },
  { name: 'Guacamole', category: 'Mexican', trending: true },
  { name: 'Churros', category: 'Mexican', trending: true },
  { name: 'Nachos', category: 'Mexican', trending: true },
  { name: 'Chiles Rellenos', category: 'Mexican', trending: false },
  { name: 'Carnitas', category: 'Mexican', trending: true },
  { name: 'Mole Chicken', category: 'Mexican', trending: false },

  // Mediterranean
  { name: 'Greek Salad', category: 'Mediterranean', trending: true },
  { name: 'Hummus', category: 'Mediterranean', trending: true },
  { name: 'Falafel', category: 'Mediterranean', trending: true },
  { name: 'Shawarma', category: 'Mediterranean', trending: true },
  { name: 'Moussaka', category: 'Mediterranean', trending: false },
  { name: 'Baklava', category: 'Mediterranean', trending: true },
  { name: 'Tzatziki', category: 'Mediterranean', trending: false },
  { name: 'Spanakopita', category: 'Mediterranean', trending: false },
  { name: 'Lamb Kofta', category: 'Mediterranean', trending: true },
  { name: 'Stuffed Grape Leaves', category: 'Mediterranean', trending: false },

  // Desserts
  { name: 'Chocolate Chip Cookies', category: 'Dessert', trending: true },
  { name: 'Cheesecake', category: 'Dessert', trending: true },
  { name: 'Brownies', category: 'Dessert', trending: true },
  { name: 'Ice Cream Sundae', category: 'Dessert', trending: true },
  { name: 'Apple Pie', category: 'Dessert', trending: true },
  { name: 'Chocolate Lava Cake', category: 'Dessert', trending: true },
  { name: 'Creme Brulee', category: 'Dessert', trending: true },
  { name: 'Panna Cotta', category: 'Dessert', trending: true },
  { name: 'Red Velvet Cake', category: 'Dessert', trending: true },
  { name: 'Key Lime Pie', category: 'Dessert', trending: true },
  { name: 'Donuts', category: 'Dessert', trending: true },
  { name: 'Cupcakes', category: 'Dessert', trending: true },
  { name: 'Macarons', category: 'Dessert', trending: true },
  { name: 'Eclairs', category: 'Dessert', trending: false },
  { name: 'Profiteroles', category: 'Dessert', trending: false },

  // Breakfast
  { name: 'Pancakes', category: 'Breakfast', trending: true },
  { name: 'French Toast', category: 'Breakfast', trending: true },
  { name: 'Waffles', category: 'Breakfast', trending: true },
  { name: 'Eggs Benedict', category: 'Breakfast', trending: true },
  { name: 'Avocado Toast', category: 'Breakfast', trending: true },
  { name: 'Breakfast Burrito', category: 'Breakfast', trending: true },
  { name: 'Omelette', category: 'Breakfast', trending: false },
  { name: 'Bagel with Lox', category: 'Breakfast', trending: true },
  { name: 'Croissant', category: 'Breakfast', trending: true },
  { name: 'Breakfast Bowl', category: 'Breakfast', trending: true },

  // Seafood
  { name: 'Grilled Salmon', category: 'Seafood', trending: true },
  { name: 'Lobster Roll', category: 'Seafood', trending: true },
  { name: 'Fish Tacos', category: 'Seafood', trending: true },
  { name: 'Shrimp Scampi', category: 'Seafood', trending: true },
  { name: 'Crab Cakes', category: 'Seafood', trending: true },
  { name: 'Tuna Poke Bowl', category: 'Seafood', trending: true },
  { name: 'Seafood Paella', category: 'Seafood', trending: true },
  { name: 'Ceviche', category: 'Seafood', trending: true },
  { name: 'Fish and Chips', category: 'Seafood', trending: true },
  { name: 'Clam Chowder', category: 'Seafood', trending: false },

  // Vegetarian
  { name: 'Veggie Burger', category: 'Vegetarian', trending: true },
  { name: 'Quinoa Bowl', category: 'Vegetarian', trending: true },
  { name: 'Stuffed Bell Peppers', category: 'Vegetarian', trending: true },
  { name: 'Eggplant Parmesan', category: 'Vegetarian', trending: true },
  { name: 'Vegetable Curry', category: 'Vegetarian', trending: true },
  { name: 'Ratatouille', category: 'Vegetarian', trending: true },
  { name: 'Mushroom Risotto', category: 'Vegetarian', trending: true },
  { name: 'Zucchini Noodles', category: 'Vegetarian', trending: true },
  { name: 'Stuffed Portobello', category: 'Vegetarian', trending: true },
  { name: 'Cauliflower Wings', category: 'Vegetarian', trending: true },

  // Soups & Stews
  { name: 'Tomato Soup', category: 'Soup', trending: false },
  { name: 'Chicken Noodle Soup', category: 'Soup', trending: true },
  { name: 'Beef Stew', category: 'Soup', trending: true },
  { name: 'Minestrone', category: 'Soup', trending: false },
  { name: 'French Onion Soup', category: 'Soup', trending: true },
  { name: 'Butternut Squash Soup', category: 'Soup', trending: true },
  { name: 'Gazpacho', category: 'Soup', trending: false },
  { name: 'Lentil Soup', category: 'Soup', trending: false },
  { name: 'Chicken Tortilla Soup', category: 'Soup', trending: true },
  { name: 'Wonton Soup', category: 'Soup', trending: true },

  // Sandwiches
  { name: 'Club Sandwich', category: 'Sandwich', trending: true },
  { name: 'Reuben Sandwich', category: 'Sandwich', trending: true },
  { name: 'BLT', category: 'Sandwich', trending: true },
  { name: 'Philly Cheesesteak', category: 'Sandwich', trending: true },
  { name: 'Cuban Sandwich', category: 'Sandwich', trending: true },
  { name: 'Banh Mi', category: 'Sandwich', trending: true },
  { name: 'Monte Cristo', category: 'Sandwich', trending: false },
  { name: 'Chicken Salad Sandwich', category: 'Sandwich', trending: false },
  { name: 'Tuna Melt', category: 'Sandwich', trending: false },
  { name: 'French Dip', category: 'Sandwich', trending: true },

  // Steaks & Grilled
  { name: 'Ribeye Steak', category: 'Grilled', trending: true },
  { name: 'Filet Mignon', category: 'Grilled', trending: true },
  { name: 'Grilled Chicken', category: 'Grilled', trending: true },
  { name: 'Lamb Chops', category: 'Grilled', trending: true },
  { name: 'Pork Tenderloin', category: 'Grilled', trending: true },
  { name: 'Brisket', category: 'Grilled', trending: true },
  { name: 'T-Bone Steak', category: 'Grilled', trending: true },
  { name: 'Skirt Steak', category: 'Grilled', trending: false },
  { name: 'Chicken Thighs', category: 'Grilled', trending: true },
  { name: 'Porterhouse', category: 'Grilled', trending: true },
];

/**
 * Select a unique food item that hasn't been posted recently
 */
export function selectUniqueFoodItem(): FoodItem {
  const recentlyPosted = recipeTracker.getPostedRecipes(30);
  const postedNames = new Set(recentlyPosted.map((r) => r.food_name));

  // Filter out recently posted items
  const availableItems = FOOD_ITEMS.filter(
    (item) => !postedNames.has(item.name)
  );

  if (availableItems.length === 0) {
    // If all items were posted recently, reset and use all items
    console.warn('All food items were posted recently. Resetting selection.');
    return selectFoodWithCategoryRotation(FOOD_ITEMS);
  }

  return selectFoodWithCategoryRotation(availableItems);
}

/**
 * Select food with category rotation and trending weight
 */
function selectFoodWithCategoryRotation(items: FoodItem[]): FoodItem {
  // Get category counts for recent posts
  const categoryCounts = new Map<string, number>();
  const categories = [...new Set(items.map((item) => item.category))];

  categories.forEach((cat) => {
    categoryCounts.set(cat, recipeTracker.getCategoryCount(cat, 7));
  });

  // Find least used category
  let leastUsedCategory = categories[0];
  let minCount = categoryCounts.get(categories[0]) || 0;

  categories.forEach((cat) => {
    const count = categoryCounts.get(cat) || 0;
    if (count < minCount) {
      minCount = count;
      leastUsedCategory = cat;
    }
  });

  // Filter items from least used category
  const categoryItems = items.filter(
    (item) => item.category === leastUsedCategory
  );

  // Weight towards trending items (70% chance)
  const trendingItems = categoryItems.filter((item) => item.trending);
  const nonTrendingItems = categoryItems.filter((item) => !item.trending);

  let candidates: FoodItem[];
  if (trendingItems.length > 0 && Math.random() < 0.7) {
    candidates = trendingItems;
  } else {
    candidates = categoryItems;
  }

  // Random selection from candidates
  return candidates[Math.floor(Math.random() * candidates.length)];
}

/**
 * Get all available food categories
 */
export function getCategories(): string[] {
  return [...new Set(FOOD_ITEMS.map((item) => item.category))];
}

