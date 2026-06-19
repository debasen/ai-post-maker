/**
 * Instagram Follow Automation Script
 *
 * Two automation modes:
 *
 *   Mode A — Explore/People page (default):
 *     followExploreSuggestions(maxFollows?)
 *       → { attempted, succeeded, skipped, errors }
 *     Navigates must already be at https://www.instagram.com/explore/people/
 *
 *   Mode B — Profile followers modal:
 *     followProfileFollowers(maxFollows?)
 *       → { attempted, succeeded, skipped, errors, modalOpened }
 *     Page must already be on the target profile URL.
 *
 * Usage (evaluate_script prepend pattern):
 *   return await followExploreSuggestions();
 *   return await followProfileFollowers();
 */

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────

const _wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function _randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function _randomDelay(minMs = 200, maxMs = 2000) {
  return _randomInt(minMs, maxMs);
}

// ─────────────────────────────────────────────────────────────
// MODE A: Explore/People page
// ─────────────────────────────────────────────────────────────

/**
 * Follows randomly selected suggested accounts on the Explore/People page.
 *
 * @param {number|null} maxFollows  Max accounts to follow (default: random 21-26).
 * @param {number|null} delayMs     Fixed delay between clicks in ms (default: random 200-2000).
 * @returns {Promise<Object>}       { attempted, succeeded, skipped, errors }
 */
async function followExploreSuggestions(maxFollows = null, delayMs = null) {
  if (!maxFollows) {
    maxFollows = _randomInt(21, 26);
  }

  console.log('🚀 [Instagram Follow] Starting explore/people randomized follow sequence...');

  const results = {
    attempted: 0,
    succeeded: 0,
    skipped: 0,
    errors: [],
  };

  if (!window.location.href.includes('instagram.com/explore/people')) {
    return { error: 'Wrong page. Please navigate to https://www.instagram.com/explore/people/ first.' };
  }

  // Collect all enabled "Follow" buttons
  const allButtons = Array.from(document.querySelectorAll('button'));
  const followButtons = allButtons.filter((btn) => {
    const text = btn.textContent ? btn.textContent.trim().toLowerCase() : '';
    return text === 'follow' && !btn.disabled;
  });

  if (followButtons.length === 0) {
    return { error: 'No follow buttons found on the page.' };
  }

  // Randomize and cap
  const shuffled = followButtons.sort(() => 0.5 - Math.random());
  const selected = shuffled.slice(0, maxFollows);

  console.log(
    `📊 [Instagram Follow] Found ${followButtons.length} suggestions. ` +
    `Randomly picking ${selected.length}.`
  );

  for (let i = 0; i < selected.length; i++) {
    const btn = selected[i];
    try {
      btn.click();
      results.succeeded++;
      console.log(`✓ [Instagram Follow] Explore: followed ${i + 1}/${selected.length}`);

      if (i < selected.length - 1) {
        const delay = delayMs !== null ? delayMs : _randomDelay(200, 2000);
        await _wait(delay);
      }
    } catch (err) {
      results.errors.push({ index: i, error: err.message });
    }
    results.attempted++;
  }

  console.log('✅ [Instagram Follow] Explore sequence complete.');
  return results;
}

// ─────────────────────────────────────────────────────────────
// MODE B: Profile followers modal
// ─────────────────────────────────────────────────────────────

/**
 * Opens the followers modal (or follows from the /followers/ page) and follows accounts.
 *
 * Works in two modes automatically:
 *   - Modal mode: When on a profile page, clicks the followers link which opens an in-page modal.
 *   - Page mode: When Instagram navigates to a standalone /followers/ URL instead of a modal,
 *               it collects Follow buttons directly from the page and scrolls to load more.
 *
 * @param {number|null} maxFollows  Max accounts to follow (default: random 23-28).
 * @param {number|null} delayMs     Fixed delay between clicks in ms (default: random 200-2000).
 * @returns {Promise<Object>}       { attempted, succeeded, skipped, errors, modalOpened, mode }
 */
async function followProfileFollowers(maxFollows = null, delayMs = null) {
  if (!maxFollows) {
    maxFollows = _randomInt(23, 28);
  }

  console.log('🚀 [Instagram Follow] Starting profile followers follow sequence...');

  const results = {
    attempted: 0,
    succeeded: 0,
    skipped: 0,
    errors: [],
    modalOpened: false,
    mode: 'unknown',
  };

  const currentUrl = window.location.href;
  const isAlreadyOnFollowersPage = currentUrl.includes('/followers');

  if (!isAlreadyOnFollowersPage) {
    // ── Step 1: We are on the profile page — click the followers link ──
    let followersLink = null;

    // First try: Find <a> elements that look like the main followers link
    const allLinks = Array.from(document.querySelectorAll('a'));
    
    // We want a link that points to followers, but not mutual/common followers
    followersLink = allLinks.find((a) => {
      const href = a.getAttribute('href') || '';
      const text = a.textContent ? a.textContent.trim().toLowerCase() : '';
      
      // If it has a /followers/ URL, make sure it's the main one, not mutual/common
      if (href.includes('/followers') && !href.includes('mutual') && !href.includes('common')) {
        return true;
      }
      
      // If it's a javascript link (like href="#") but contains the main "followers" text
      if (text.includes('followers') && !text.includes('following') && !text.includes('followed by') && !text.includes('mutual')) {
        return true;
      }
      
      return false;
    });

    if (!followersLink) {
      // Fallback: search spans/buttons/divs for text content
      const found = Array.from(document.querySelectorAll('a, span, button, div[role="button"]')).find((el) => {
        const text = el.textContent ? el.textContent.trim().toLowerCase() : '';
        return text.includes('followers') && !text.includes('following') && !text.includes('followed by') && !text.includes('mutual');
      });
      if (found) {
        followersLink = found;
      }
    }

    if (followersLink) {
      console.log('📌 [Instagram Follow] Clicking followers element:', followersLink.outerHTML.substring(0, 150));
      followersLink.click();
    } else {
      return { error: 'Followers link not found on this profile page.' };
    }

    // Wait for modal or page navigation
    await _wait(2500);
  }

  // ── Step 2: Determine whether we are in modal or page mode ──
  const afterUrl = window.location.href;
  const isPageMode = afterUrl.includes('/followers');

  if (isPageMode) {
    results.mode = 'page';
    results.modalOpened = false;
    console.log('📋 [Instagram Follow] Detected standalone followers page mode.');
  } else {
    results.mode = 'modal';
    results.modalOpened = true;
    console.log('📋 [Instagram Follow] Detected followers modal mode.');
  }

  // ── Step 3: Locate scroll container (modal mode) or use document (page mode) ──
  let scrollContainer = null;

  if (!isPageMode) {
    scrollContainer =
      document.querySelector('div[style*="overflow: hidden auto"]') ||
      document.querySelector('div[style*="overflow-y: auto"]');

    if (!scrollContainer) {
      const modalHeading = Array.from(document.querySelectorAll('[role="heading"]')).find(
        (h) => h.textContent && h.textContent.trim() === 'Followers'
      );
      if (modalHeading) {
        scrollContainer = modalHeading.closest('div[class]');
      }
    }
  }

  // ── Step 4: Scroll to load more followers ─────────────────
  const scrollTarget = scrollContainer || document.documentElement;
  for (let s = 0; s < 4; s++) {
    if (scrollContainer) {
      scrollContainer.scrollTop = scrollContainer.scrollHeight;
    } else {
      window.scrollTo(0, document.body.scrollHeight);
    }
    await _wait(800);
  }

  // ── Step 5: Collect "Follow" buttons ──────────────────────
  const allButtons = Array.from(document.querySelectorAll('button'));
  const followButtons = allButtons.filter((btn) => {
    const text = btn.textContent ? btn.textContent.trim().toLowerCase() : '';
    const isFollow = text === 'follow';
    const isInScope = scrollContainer ? scrollContainer.contains(btn) : true;
    return isFollow && !btn.disabled && isInScope;
  });

  if (followButtons.length === 0) {
    return {
      error:
        'No follow buttons found. The account may be private, all followers may already be followed, ' +
        'or the page did not load correctly.',
    };
  }

  const targetCount = Math.min(followButtons.length, maxFollows);
  console.log(
    `📊 [Instagram Follow] Found ${followButtons.length} followable accounts. ` +
    `Picking ${targetCount} randomly. Mode: ${results.mode}`
  );

  // Randomize and cap
  const shuffled = followButtons.sort(() => 0.5 - Math.random());
  const selected = shuffled.slice(0, targetCount);

  // ── Step 6: Click each selected button ────────────────────
  for (let i = 0; i < selected.length; i++) {
    const btn = selected[i];
    try {
      btn.scrollIntoView({ behavior: 'smooth', block: 'center' });
      await _wait(300);
      btn.click();
      results.succeeded++;
      console.log(`✓ [Instagram Follow] Profile: followed ${i + 1}/${selected.length}`);

      if (i < selected.length - 1) {
        const delay = delayMs !== null ? delayMs : _randomDelay(200, 2000);
        await _wait(delay);
      }
    } catch (err) {
      results.errors.push({ index: i, error: err.message });
    }
    results.attempted++;
  }

  console.log('✅ [Instagram Follow] Profile followers sequence complete.');
  return results;
}

// ─────────────────────────────────────────────────────────────
// Export (Node / CommonJS environments)
// ─────────────────────────────────────────────────────────────
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    followExploreSuggestions,
    followProfileFollowers,
  };
}
