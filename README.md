# AI Food Video Workflow

Automated workflow that generates realistic food images, animates them into videos, creates matching recipes, and posts to Facebook Reels twice daily.

## Features

- 🎨 **AI Image Generation**: Uses Nano Banana Pro via Monica API for hyper-realistic food images
- 🎬 **Video Animation**: Converts images to videos using Kling AI
- 📝 **Recipe Generation**: Creates detailed recipes using GPT-4.1
- 📤 **Auto-Posting**: Automatically posts to Facebook Reels with optimized captions
- 🔄 **Duplicate Prevention**: Tracks posted recipes to avoid repetition
- ⏰ **Scheduled Execution**: Runs twice daily (8 AM and 6 PM) via cron

## Prerequisites

- Node.js 18+ 
- TypeScript 5.6+
- Monica AI API account with paid subscription
- Facebook Page with Graph API access

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Configure environment variables:**
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and add your API keys:
   - `MONICA_API_KEY`: Your Monica API key from [platform.monica.im](https://platform.monica.im/)
   - `FB_APP_ID`: Facebook App ID
   - `FB_APP_SECRET`: Facebook App Secret
   - `FB_PAGE_ID`: Your Facebook Page ID
   - `FB_PAGE_ACCESS_TOKEN`: Long-lived Page Access Token

3. **Build the project:**
   ```bash
   npm run build
   ```

## Usage

### Development Mode
```bash
npm run dev
```

### Production Mode
```bash
npm start
```

### Test Workflow (Dry Run)
Modify `src/index.ts` to use `testWorkflow()` instead of `generateAndPostFoodReel()` for testing without posting.

## Project Structure

```
ai-post-maker/
├── src/
│   ├── index.ts              # Main entry point with cron scheduler
│   ├── config.ts             # Configuration and environment variables
│   ├── workflow.ts           # Main workflow orchestration
│   ├── services/
│   │   ├── monica/           # Monica AI API services
│   │   │   ├── client.ts     # API client setup
│   │   │   ├── image.ts      # Image generation
│   │   │   ├── video.ts      # Video animation
│   │   │   └── chat.ts       # Recipe text generation
│   │   └── facebook.ts       # Facebook Reels upload
│   ├── database/
│   │   ├── db.ts             # SQLite database setup
│   │   └── recipes.ts        # Recipe tracking
│   ├── prompts/
│   │   ├── imagePrompts.ts   # Image generation prompts
│   │   └── recipePrompts.ts  # Recipe generation prompts
│   └── utils/
│       ├── foodSelector.ts   # Food selection logic
│       └── fileManager.ts    # File management utilities
├── data/                     # SQLite database storage
├── temp/                     # Temporary media files
└── dist/                     # Compiled JavaScript (after build)
```

## Configuration

### Schedule
Edit `src/config.ts` to change the cron schedule. Default is `'0 8,18 * * *'` (8 AM and 6 PM daily).

### Models
You can switch AI models in `src/services/monica/client.ts`:
- **Image**: `nano-banana-pro`, `flux-pro`, `dall-e-3`, etc.
- **Video**: `kling-ai`, `runway-gen3`, `pika-ai`, etc.
- **Chat**: `gpt-4.1`, `claude-opus-4`, `gemini-2.5-pro`, etc.

## Facebook Setup

1. Create a Facebook App at [developers.facebook.com](https://developers.facebook.com/)
2. Add `pages_manage_posts` and `pages_read_engagement` permissions
3. Generate a long-lived Page Access Token
4. Add your Page ID and Access Token to `.env`

**Note**: Music cannot be added programmatically to Reels via API. The workflow includes a reminder in the description to add trending music manually.

## Limitations

- Facebook API cannot add trending music programmatically
- Monica API balance is separate from subscription (requires separate funding)
- Long-lived Facebook tokens expire (implement refresh logic if needed)
- Rate limits may apply (delays are built-in between operations)

## Future Enhancements

- Multi-angle videos (4-5 images from different angles)
- Instagram and YouTube posting
- Analytics tracking
- A/B testing for prompts
- Automatic token refresh for Facebook

## License

MIT

