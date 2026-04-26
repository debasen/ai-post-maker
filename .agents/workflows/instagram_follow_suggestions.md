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

### Step 2: Execute First Randomized Follow Phase
Inject and evaluate the following asynchronous JavaScript snippet. It will randomly pick between 7-12 accounts from the suggestions and follow them.

```javascript
/**
 * Executes the complete Instagram Follow Suggestions automation sequence.
 * Randomly picks accounts to follow instead of top-down selection.
 * @param {number} maxFollows The maximum number of people to follow (default: random 7-12).
 * @param {number} delayMs The delay between clicks in milliseconds (default: 1500).
 * @returns {Promise<Object>} An object containing results { attempted, succeeded, skipped, errors }
 */
async function automateInstagramFollows(maxFollows, delayMs = 1500) {
  if (!maxFollows) {
    maxFollows = Math.floor(Math.random() * (12 - 7 + 1)) + 7;
  }
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  console.log("🚀 [Instagram Automation] Starting randomized follow sequence...");
  
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
    return { error: 'No follow buttons found.' };
  }

  console.log(`📊 [Instagram Automation] Found ${followButtons.length} total suggestions. Picked ${Math.min(followButtons.length, maxFollows)} randomly.`);

  // Randomize selection
  const shuffled = followButtons.sort(() => 0.5 - Math.random());
  const selected = shuffled.slice(0, maxFollows);

  for (let i = 0; i < selected.length; i++) {
    const btn = selected[i];
    try {
      btn.click();
      results.succeeded++;
      console.log(`✓ [Instagram Automation] Followed account ${i + 1}/${selected.length}`);
      
      if (i < selected.length - 1) {
        await wait(delayMs);
      }
    } catch (err) {
      results.errors.push({ index: i, error: err.message });
    }
    results.attempted++;
  }

  console.log("✅ [Instagram Automation] Sequence complete.");
  return results;
}

// Usage: return await automateInstagramFollows(null, 1500);
```

### Step 3: Reload and Repeat
- Use `navigate_page` with action `reload` to refresh the suggestions.
- Wait for the page to load (approx. 2-3 seconds).
- Execute the same script again to follow another 7-12 random accounts.

### Step 4: Track and Report Results
- Report the combined results (total successful follows) to the user.
- Note any errors.
- **Status indicators after clicking:**
  - "Following" - Public account, immediately followed
  - "Requested" - Private account, follow request sent (requires approval)
  - Button disabled - Action in progress or completed

## Warnings
- Instagram has rate limits for follow actions.
- Excessive following may trigger account restrictions.
- This tool should be used responsibly and in moderation.
