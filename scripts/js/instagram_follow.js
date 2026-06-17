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
 * Opens the followers modal on the current profile page and follows accounts.
 *
 * @param {number|null} maxFollows  Max accounts to follow (default: random 23-28).
 * @param {number|null} delayMs     Fixed delay between clicks in ms (default: random 200-2000).
 * @returns {Promise<Object>}       { attempted, succeeded, skipped, errors, modalOpened }
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
  };

  // ── Step 1: Click the followers link ──────────────────────
  const followersLink = Array.from(document.querySelectorAll('a')).find((a) => {
    const href = a.getAttribute('href') || '';
    return href.includes('/followers/');
  });

  if (!followersLink) {
    // Fallback: find by text content
    const found = Array.from(document.querySelectorAll('a, span')).find((el) => {
      const text = el.textContent ? el.textContent.trim().toLowerCase() : '';
      return text.includes('followers') && !text.includes('following');
    });
    if (found) {
      found.click();
    } else {
      return { error: 'Followers link not found on this profile page.' };
    }
  } else {
    followersLink.click();
  }

  // Wait for modal to open
  await _wait(2000);
  results.modalOpened = true;

  // ── Step 2: Locate the scrollable container ────────────────
  let scrollContainer =
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

  // ── Step 3: Scroll to load more followers ─────────────────
  if (scrollContainer) {
    for (let s = 0; s < 3; s++) {
      scrollContainer.scrollTop = scrollContainer.scrollHeight;
      await _wait(800);
    }
  }

  // ── Step 4: Collect "Follow" buttons inside the modal ─────
  const allButtons = Array.from(document.querySelectorAll('button'));
  const followButtons = allButtons.filter((btn) => {
    const text = btn.textContent ? btn.textContent.trim().toLowerCase() : '';
    const isFollow = text === 'follow';
    const isInModal = scrollContainer ? scrollContainer.contains(btn) : true;
    return isFollow && !btn.disabled && isInModal;
  });

  if (followButtons.length === 0) {
    return {
      error:
        'No follow buttons found in followers modal. ' +
        'The account may be private or restrict followers visibility.',
    };
  }

  const targetCount = Math.min(followButtons.length, maxFollows);
  console.log(
    `📊 [Instagram Follow] Found ${followButtons.length} followable accounts in modal. ` +
    `Picking ${targetCount} randomly.`
  );

  // Randomize and cap
  const shuffled = followButtons.sort(() => 0.5 - Math.random());
  const selected = shuffled.slice(0, targetCount);

  // ── Step 5: Click each selected button ────────────────────
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
