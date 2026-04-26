---
name: Instagram Follow Suggestions (BrowserOS Integrated)
description: End-to-end automation skill for sending follow requests to suggested people on Instagram's explore page using browseros evaluate_script.
---

# Instagram Follow Suggestions

## When to Use

Activate when the user wants to send follow requests to suggested people on Instagram's explore page at https://www.instagram.com/explore/people/

## Steps

### Step 1: Ensure Browser Context
- Ensure you have a browser window active on Instagram's explore/people page: https://www.instagram.com/explore/people/
- If not already on the correct interface, navigate there using the `navigate_page` tool from the browseros MCP.

### Step 2: Execute Unified Automation Script
Inject and evaluate the following asynchronous JavaScript snippet into the active Instagram tab using the `evaluate_script` tool from the browseros MCP. You can adjust `maxFollows` and `delayMs` as needed.

```javascript
/**
 * Executes the complete Instagram Follow Suggestions automation sequence.
 * @param {number} maxFollows The maximum number of people to follow (default: 10).
 * @param {number} delayMs The delay between clicks in milliseconds (default: 1000).
 * @returns {Promise<Object>} An object containing results { attempted, succeeded, skipped, errors }
 */
async function automateInstagramFollows(maxFollows = 10, delayMs = 1000) {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  console.log("🚀 [Instagram Automation] Starting follow sequence...");
  
  const results = {
    attempted: 0,
    succeeded: 0,
    skipped: 0,
    errors: []
  };

  if (!window.location.href.includes('instagram.com/explore/people')) {
    return { error: 'Please navigate to https://www.instagram.com/explore/people/ first' };
  }

  // Find all "Follow" buttons
  const buttons = Array.from(document.querySelectorAll('button'));
  const followButtons = buttons.filter(btn => {
    const text = btn.textContent ? btn.textContent.trim().toLowerCase() : '';
    return text === 'follow' && !btn.disabled;
  });

  if (followButtons.length === 0) {
    return { error: 'No follow buttons found. All accounts may already be followed or the page structure has changed.' };
  }

  console.log(`📊 [Instagram Automation] Found ${followButtons.length} accounts to follow`);

  const limit = Math.min(followButtons.length, maxFollows);
  for (let i = 0; i < limit; i++) {
    const btn = followButtons[i];
    try {
      btn.click();
      results.succeeded++;
      console.log(`✓ [Instagram Automation] Followed account ${i + 1}/${limit}`);
      
      // Wait before next click to avoid rate limiting
      if (i < limit - 1) {
        await wait(delayMs);
      }
    } catch (err) {
      results.errors.push({ index: i, error: err.message });
      console.error(`✗ [Instagram Automation] Failed to follow account ${i + 1}: ${err.message}`);
    }
    results.attempted++;
  }

  console.log("✅ [Instagram Automation] Follow sequence complete.");
  return results;
}

// Usage: return await automateInstagramFollows(10, 1000);
```

### Step 3: Track and Report Results
Once the script successfully executes and returns the results object:
- Report the results to the user with the count of successful follow requests sent.
- Note any errors.
- **Status indicators after clicking:**
  - "Following" - Public account, immediately followed
  - "Requested" - Private account, follow request sent (requires approval)
  - Button disabled - Action in progress or completed

## Warnings
- Instagram has rate limits for follow actions.
- Excessive following may trigger account restrictions.
- This tool should be used responsibly and in moderation.
