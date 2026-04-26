---
name: instagram-follow-suggestions
description: Automatically send follow requests to suggested people on Instagram's "Explore People" page (instagram.com/explore/people/). Use when the user wants to follow multiple suggested accounts quickly.
metadata:
  display-name: Instagram Follow Suggestions
  enabled: "true"
  version: "1.0"
  author: "BrowserOS"
---

# Instagram Follow Suggestions

## When to Use

Activate when the user wants to send follow requests to suggested people on Instagram's explore page at https://www.instagram.com/explore/people/

## Steps

1. **Verify page location.** Ensure we're on Instagram's explore/people page. If not, navigate there.

2. **Configure parameters:**
   - `maxFollows`: Maximum number of people to follow (default: 10)
   - `delayMs`: Delay between follow clicks in milliseconds (default: 1000)

3. **Scan for follow buttons.** Look for buttons with text "Follow" in the suggested people list.

4. **Click each follow button** up to `maxFollows`, with `delayMs` delay between each.

5. **Track results:**
   - Count successful follows
   - Note any errors (button changed to "Requested" or "Following")
   - Stop if page changes or no more follow buttons found

6. **Report results** to the user with count of successful follow requests sent.

## Implementation

```javascript
// instagram-follow-suggestions.js
async function instagramFollowSuggestions(params) {
  const { maxFollows = 10, delayMs = 1000 } = params;
  const results = {
    attempted: 0,
    succeeded: 0,
    skipped: 0,
    errors: []
  };

  // Get current page
  const pages = await list_pages();
  const page = pages.find(p => p.url.includes('instagram.com/explore/people'));
  
  if (!page) {
    return { error: 'Please navigate to https://www.instagram.com/explore/people/ first' };
  }

  // Take snapshot to find follow buttons
  let snapshot = await take_snapshot({ page: page.id });
  
  // Find all "Follow" buttons - filter for enabled buttons with text "Follow"
  // Skip buttons that are already disabled or show "Following"/"Requested"
  const followButtons = snapshot.elements.filter(el => 
    el.type === 'button' && 
    el.name && 
    el.name.toLowerCase() === 'follow' &&
    !el.disabled
  );

  if (followButtons.length === 0) {
    return { error: 'No follow buttons found. All accounts may already be followed or the page structure has changed.' };
  }

  console.log(`Found ${followButtons.length} accounts to follow`);

  // Click each follow button
  for (let i = 0; i < Math.min(followButtons.length, maxFollows); i++) {
    const button = followButtons[i];
    
    try {
      await click({ page: page.id, element: button.id });
      results.succeeded++;
      console.log(`✓ Followed account ${i + 1}/${Math.min(followButtons.length, maxFollows)}`);
      
      // Wait before next click to avoid rate limiting
      if (i < Math.min(followButtons.length, maxFollows) - 1) {
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    } catch (err) {
      results.errors.push({ button: button.id, error: err.message });
      console.log(`✗ Failed to follow account ${i + 1}: ${err.message}`);
    }
    
    results.attempted++;
  }

  return results;
}
```

## Output Format

```
Instagram Follow Suggestions Complete

✅ Successfully sent follow requests: {succeeded}
❌ Failed attempts: {errors.length}
📊 Total processed: {attempted}

Status indicators after clicking:
• "Following" - Public account, immediately followed
• "Requested" - Private account, follow request sent (requires approval)
• Button disabled - Action in progress or completed

Note: Instagram may rate-limit excessive follow actions. Use responsibly.
```

## Warnings

- Instagram has rate limits for follow actions
- Excessive following may trigger account restrictions
- This tool should be used responsibly and in moderation
- Some accounts may require approval for follow requests (private accounts)
