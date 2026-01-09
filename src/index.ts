import cron from 'node-cron';
import { config } from './config.js';
import { generateAndPostFoodReel } from './workflow.js';

/**
 * Main entry point for the AI Food Video Workflow
 */
async function main() {
  console.log('🚀 AI Food Video Workflow Starting...');
  console.log(`📅 Schedule: ${config.schedule.cron}`);
  console.log('⏰ Twice daily: 8 AM and 6 PM\n');

  // Schedule the workflow to run twice daily
  cron.schedule(config.schedule.cron, async () => {
    console.log('\n⏰ Scheduled run triggered');
    console.log('='.repeat(50));
    
    try {
      await generateAndPostFoodReel();
    } catch (error) {
      console.error('❌ Scheduled run failed:', error);
    }
    
    console.log('='.repeat(50));
    console.log('✅ Scheduled run completed\n');
  });

  // Run immediately on startup (optional - comment out if not desired)
  console.log('🔄 Running initial workflow...');
  try {
    await generateAndPostFoodReel();
  } catch (error) {
    console.error('❌ Initial run failed:', error);
  }

  console.log('\n✅ Scheduler started. Waiting for scheduled runs...');
  console.log('Press Ctrl+C to stop.\n');
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n👋 Shutting down gracefully...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n👋 Shutting down gracefully...');
  process.exit(0);
});

// Start the application
main().catch((error) => {
  console.error('❌ Fatal error:', error);
  process.exit(1);
});

