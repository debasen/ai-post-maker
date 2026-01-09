import dotenv from 'dotenv';

dotenv.config();

export const config = {
  monica: {
    apiKey: process.env.MONICA_API_KEY || '',
    baseURL: 'https://openapi.monica.im/v1',
  },
  facebook: {
    appId: process.env.FB_APP_ID || '',
    appSecret: process.env.FB_APP_SECRET || '',
    pageId: process.env.FB_PAGE_ID || '',
    pageAccessToken: process.env.FB_PAGE_ACCESS_TOKEN || '',
  },
  database: {
    path: './data/recipes.db',
  },
  temp: {
    dir: './temp',
  },
  schedule: {
    cron: '0 8,18 * * *', // Twice daily: 8 AM and 6 PM
  },
};

// Validate required environment variables
const requiredVars = [
  'MONICA_API_KEY',
  'FB_APP_ID',
  'FB_APP_SECRET',
  'FB_PAGE_ID',
  'FB_PAGE_ACCESS_TOKEN',
];

const missingVars = requiredVars.filter(
  (varName) => !process.env[varName]
);

if (missingVars.length > 0) {
  console.warn(
    `Warning: Missing environment variables: ${missingVars.join(', ')}`
  );
}

