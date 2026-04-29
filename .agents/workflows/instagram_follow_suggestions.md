---
name: Instagram Follow Suggestions (BrowserOS Integrated)
description: End-to-end automation skill for sending follow requests to suggested people on Instagram's explore page or from a specific profile's followers list using browseros evaluate_script.
arguments:
  profile_url:
    type: string
    description: Optional Instagram profile URL (e.g., https://www.instagram.com/username/). If provided, follows from the profile's followers modal instead of explore/people.
    required: false
---

# Instagram Follow Suggestions

## When to Use

Activate when the user wants to send follow requests to suggested people on Instagram's explore page at https://www.instagram.com/explore/people/ or from a specific profile's followers list.

## Steps

### Step 1: Determine Mode and Navigate

**Default Mode (no profile_url):**
- Ensure you have a browser window active on Instagram's explore/people page: https://www.instagram.com/explore/people/
- If not already on the correct interface, navigate there using the `navigate_page` tool from the browseros MCP.

**Profile Followers Mode (profile_url provided):**
- Navigate to the provided profile URL using `navigate_page`.
- Wait for the page to fully load (approx. 2-3 seconds).

### Step 2a: Execute Randomized Follow on Explore Page (Default Mode)

Inject and evaluate the following asynchronous JavaScript snippet. It will randomly pick between 7-12 accounts from the suggestions and follow them.

```javascript
/**
 * Executes the Instagram Follow Suggestions automation on explore/people.
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

### Step 2b: Execute Randomized Follow from Profile Followers Modal (Profile Mode)

Inject and evaluate the following asynchronous JavaScript snippet. It will open the followers modal, then randomly pick between 23-28 accounts and follow them.

```javascript
/**
 * Executes the Instagram Profile Followers automation sequence.
 * Opens the followers modal and randomly follows accounts.
 * @param {number} maxFollows The maximum number of people to follow (default: random 23-28).
 * @param {number} delayMs The delay between clicks in milliseconds (default: 1500).
 * @returns {Promise<Object>} An object containing results { attempted, succeeded, skipped, errors, modalOpened }
 */
async function automateProfileFollowers(maxFollows, delayMs = 1500) {
  if (!maxFollows) {
    maxFollows = Math.floor(Math.random() * (28 - 23 + 1)) + 23;
  }
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  console.log("🚀 [Instagram Automation] Starting profile followers follow sequence...");
  
  const results = {
    attempted: 0,
    succeeded: 0,
    skipped: 0,
    errors: [],
    modalOpened: false
  };

  // Step 1: Click the followers link
  const followersLink = Array.from(document.querySelectorAll('a')).find(a => {
    const href = a.getAttribute('href') || '';
    return href.includes('/followers/');
  });

  if (!followersLink) {
    // Fallback: try finding by text content
    const allLinks = Array.from(document.querySelectorAll('a, span'));
    const found = allLinks.find(el => {
      const text = el.textContent ? el.textContent.trim().toLowerCase() : '';
      return text.includes('followers') && !text.includes('following');
    });
    if (found) {
      found.click();
    } else {
      return { error: 'Followers link not found on this profile.' };
    }
  } else {
    followersLink.click();
  }

  // Wait for modal to open
  await wait(2000);
  results.modalOpened = true;

  // Step 2: Find the modal and scrollable container
  let scrollContainer = document.querySelector('div[style*="overflow: hidden auto"]');
  if (!scrollContainer) {
    scrollContainer = document.querySelector('div[style*="overflow-y: auto"]');
  }
  if (!scrollContainer) {
    // Try finding by role or heading
    const modalHeading = Array.from(document.querySelectorAll('[role="heading"]')).find(h => 
      h.textContent && h.textContent.trim() === 'Followers'
    );
    if (modalHeading) {
      scrollContainer = modalHeading.closest('div[class]');
    }
  }

  // Step 3: Scroll to load more followers if needed
  if (scrollContainer) {
    for (let s = 0; s < 3; s++) {
      scrollContainer.scrollTop = scrollContainer.scrollHeight;
      await wait(800);
    }
  }

  // Step 4: Find all "Follow" buttons in the modal
  const allButtons = Array.from(document.querySelectorAll('button'));
  const followButtons = allButtons.filter(btn => {
    const text = btn.textContent ? btn.textContent.trim().toLowerCase() : '';
    const isFollow = text === 'follow';
    const isInModal = scrollContainer ? scrollContainer.contains(btn) : true;
    return isFollow && !btn.disabled && isInModal;
  });

  if (followButtons.length === 0) {
    return { error: 'No follow buttons found in followers modal. The account may be private or have restricted followers visibility.' };
  }

  const targetCount = Math.min(followButtons.length, maxFollows);
  console.log(`📊 [Instagram Automation] Found ${followButtons.length} followable accounts in modal. Picked ${targetCount} randomly.`);

  // Randomize selection
  const shuffled = followButtons.sort(() => 0.5 - Math.random());
  const selected = shuffled.slice(0, targetCount);

  for (let i = 0; i < selected.length; i++) {
    const btn = selected[i];
    try {
      btn.scrollIntoView({ behavior: 'smooth', block: 'center' });
      await wait(300);
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

  console.log("✅ [Instagram Automation] Profile followers sequence complete.");
  return results;
}

// Usage: return await automateProfileFollowers(null, 1500);
```

### Step 3: Reload and Repeat (Default Mode Only)

For the default explore/people mode:
- Use `navigate_page` with action `reload` to refresh the suggestions.
- Wait for the page to load (approx. 2-3 seconds).
- Execute the same script again to follow another 7-12 random accounts.

For profile followers mode:
- The modal closes after following. To continue, reopen the followers modal by clicking the followers link again and re-run the script.

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
- When following from a profile's followers list, be aware that some accounts may show "Only [username] can see all followers" if the profile is private.
