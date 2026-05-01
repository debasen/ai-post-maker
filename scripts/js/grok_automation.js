/**
 * Grok Image-to-Video Automation Script (v5)
 *
 * UI Discovery Notes (2026-04-28):
 * - Completed video page: <video> element present with .mp4 src,
 *   button[aria-label="Pause"] ENABLED exists, button[aria-label="Download"] ENABLED exists.
 * - Image-only post page: no <video>, button[aria-label="Make video"] visible & enabled.
 * - Loading state: "Generating" text + "Cancel Video" button visible.
 * - Video moderation: svg.lucide-eye-off present after generation step.
 * - Image moderation: img[alt="Moderated"] with blur-lg saturate-0 classes.
 * - Failure text: body text contains moderation/error keywords.
 * - More options menu: contains [Custom, Spicy, Normal] menuitems.
 * - Image/Video radio toggle present on posts.
 * - IMPORTANT: Disabled Pause/Download buttons do NOT indicate success.
 *
 * Two-Phase API:
 *   Phase A: automateGrokGeneration({ ... }) → { status: 'video_generating', videoUrl, postUrl, mode }
 *   Phase B: checkVideoCompletion() → { status: 'completed'|'video_warning'|'image_warning', videoUrl, error }
 *
 * Usage:
 *   await automateGrokGeneration({
 *     promptText, thumbnailId, videoPromptText, videoType,
 *     skipImageGeneration, postUrl
 *   });
 *   // ... sleep ...
 *   await checkVideoCompletion();
 */

// ─────────────────────────────────────────────────────────────
// SELECTORS & CONFIG (populated from live MCP UI exploration)
// ─────────────────────────────────────────────────────────────
const SELECTORS = {
  // Inputs
  promptInput: '[placeholder="Type to imagine, @ to reference images"]',
  promptInputData: '[data-placeholder="Type to imagine, @ to reference images"]',
  contentEditable: '[contenteditable="true"]',

  // Submit buttons
  submitBtn: 'button[aria-label="Edit"], button[aria-label="Grok"], button[aria-label="Send"]',

  // Video generation trigger
  makeVideoBtn: 'button[aria-label="Make video"]',

  // More options / Spicy
  moreOptionsBtn: 'button[aria-label="More options"], button[aria-label="More"]',
  spicyMenuItem: "//div[@role='menuitem']//div[normalize-space()='Spicy']",

  // Success indicators
  videoElement: 'video',
  pauseBtn: 'button[aria-label="Pause"]',
  downloadBtn: 'button[aria-label="Download"]',

  // Moderation indicators
  eyeOffSvg: 'svg.lucide-eye-off',

  // Failure text patterns (checked against document.body.innerText)
  failurePatterns: [
    /moderated/i,
    /unable to generate/i,
    /failed/i,
    /restricted/i,
    /policy/i,
    /cannot create/i,
    /blocked/i,
    /content not available/i,
    /error generating/i,
  ],
};

const POLLING = {
  videoCompletionIntervalMs: 3000,
  videoCompletionMaxAttempts: 120, // ~6 minutes
  urlChangeIntervalMs: 2000,
  urlChangeMaxAttempts: 15, // ~30 seconds
  imageGenerationIntervalMs: 2000,
  imageGenerationMaxAttempts: 60, // ~2 minutes
};

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const clickElement = (el) => {
  if (!el) return;
  el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true }));
  el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
  el.click();
  el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, cancelable: true }));
  el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
};

const findVisibleMakeVideoButton = () => {
  const btns = Array.from(document.querySelectorAll(SELECTORS.makeVideoBtn));
  // Prefer visible, non-disabled buttons
  const candidates = btns.filter((b) => {
    const rect = b.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && !b.disabled && b.offsetParent !== null;
  });
  if (candidates.length > 0) return candidates[0];
  return null;
};

const detectVideoSuccess = () => {
  const video = document.querySelector(SELECTORS.videoElement);
  if (video && video.src && video.src.includes('.mp4')) {
    return { success: true, videoUrl: window.location.href };
  }
  // Only count Pause/Download as success if they are ENABLED
  const pauseBtn = document.querySelector(SELECTORS.pauseBtn);
  const downloadBtn = document.querySelector(SELECTORS.downloadBtn);
  if (pauseBtn && !pauseBtn.disabled) {
    return { success: true, videoUrl: window.location.href };
  }
  if (downloadBtn && !downloadBtn.disabled) {
    return { success: true, videoUrl: window.location.href };
  }
  return { success: false };
};

const detectModeration = () => {
  const eyeOff = document.querySelector(SELECTORS.eyeOffSvg);
  if (eyeOff) {
    return { moderated: true, reason: 'svg.lucide-eye-off detected' };
  }
  return { moderated: false };
};

const detectVideoFailure = () => {
  const bodyText = document.body ? document.body.innerText : '';
  for (const pattern of SELECTORS.failurePatterns) {
    if (pattern.test(bodyText)) {
      return { failed: true, reason: pattern.source };
    }
  }
  return { failed: false };
};

// ─────────────────────────────────────────────────────────────
// PHASE 1: IMAGE GENERATION
// ─────────────────────────────────────────────────────────────
async function runImageGeneration(promptText) {
  console.log('📸 [Grok v5] Starting image generation...');

  // Step 1A: Click thumbnail
  try {
    await wait(2000);
    const img = document.querySelector('img[alt="Thumbnail 1"]');
    if (img) {
      clickElement(img);
      await wait(2000);
      console.log('📸 [Grok v5] Clicked first thumbnail (img[alt="Thumbnail 1"]).');
    } else {
      console.warn('⚠️ [Grok v5] First thumbnail (img[alt="Thumbnail 1"]) not found.');
    }
  } catch (err) {
    console.error('❌ [Grok v5] Thumbnail click error:', err);
  }

  // Step 1B: Find input
  const editableElement =
    document.querySelector(SELECTORS.promptInput) ||
    document.querySelector(SELECTORS.promptInputData) ||
    document.querySelector(SELECTORS.contentEditable);

  if (!editableElement) {
    throw new Error('Prompt input box not found.');
  }

  clickElement(editableElement);
  editableElement.focus();
  await wait(500);

  // Step 1C: Type prompt
  editableElement.textContent = promptText;
  editableElement.dispatchEvent(new Event('input', { bubbles: true }));
  editableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(500);

  // Step 1D: Submit
  let submitBtn = document.querySelector(SELECTORS.submitBtn);
  if (!submitBtn) {
    const buttons = Array.from(document.querySelectorAll('button'));
    submitBtn = buttons.reverse().find((b) => {
      const rect = b.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
  }

  if (!submitBtn) {
    throw new Error('Submit button not found.');
  }

  clickElement(submitBtn);
  console.log('⏳ [Grok v5] Image prompt submitted. Waiting for generation...');

  // Step 1E: Wait for "Make video" button to appear and be enabled
  for (let i = 0; i < POLLING.imageGenerationMaxAttempts; i++) {
    await wait(POLLING.imageGenerationIntervalMs);

    const btn = findVisibleMakeVideoButton();
    if (btn) {
      console.log('✅ [Grok v5] Image generation complete (Make video button visible).');
      await wait(6000);
      return { postUrl: window.location.href };
    }

    const moderation = detectModeration();
    if (moderation.moderated) {
      throw new Error(`IMAGE_MODERATED: ${moderation.reason}`);
    }

    if (i % 5 === 0) console.log(`⏳ [Grok v5] Waiting for image generation... attempt ${i + 1}/${POLLING.imageGenerationMaxAttempts}`);
  }

  throw new Error('IMAGE_GENERATION_TIMEOUT: Neither Make video button nor image moderation detected after 2 minutes.');
}

// ─────────────────────────────────────────────────────────────
// PHASE 2: VIDEO GENERATION TRIGGER
// ─────────────────────────────────────────────────────────────
async function triggerVideoGeneration(mode, videoPromptText, videoType) {
  const postUrl = window.location.href;

  // ── Spicy Mode ──
  if (mode === 'spicy') {
    console.log('🌶️ [Grok v5] Spicy mode...');
    const btns = Array.from(document.querySelectorAll('button'));
    const moreOptionsBtn = btns.find(
      (b) =>
        b.getAttribute('aria-label') === 'More options' ||
        b.getAttribute('aria-label') === 'More' ||
        (b.getAttribute('aria-label') || '').includes('More')
    );

    if (!moreOptionsBtn) {
      console.warn("⚠️ [Grok v5] 'More options' not found. Falling back to default Make video.");
      return triggerDefaultMakeVideo(postUrl);
    }

    if (moreOptionsBtn.getAttribute('aria-expanded') !== 'true') {
      clickElement(moreOptionsBtn);
      await wait(1500);
    }

    let spicyBtn = null;
    try {
      spicyBtn = document.evaluate(
        SELECTORS.spicyMenuItem,
        document,
        null,
        XPathResult.FIRST_ORDERED_NODE_TYPE,
        null
      ).singleNodeValue;
    } catch (e) { }

    if (!spicyBtn) {
      const menuItems = Array.from(document.querySelectorAll('[role="menuitem"]'));
      spicyBtn = menuItems.find((el) => el.textContent && el.textContent.includes('Spicy'));
    }

    if (!spicyBtn) {
      console.warn("⚠️ [Grok v5] 'Spicy' not found. Falling back to default Make video.");
      document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      await wait(1000);
      return triggerDefaultMakeVideo(postUrl);
    }

    const oldUrl = window.location.href;
    clickElement(spicyBtn);
    console.log('⏳ [Grok v5] Spicy clicked. Waiting for URL change...');
    const urlResult = await waitForUrlChange(oldUrl);
    return { mode: 'spicy_video', postUrl, ...urlResult };
  }

  // ── Custom Video Prompt Mode ──
  if (mode === 'custom_video_prompt') {
    console.log('🎬 [Grok v5] Custom video prompt mode...');

    // Step V-1: Click Video icon
    const allBtns = Array.from(document.querySelectorAll('button'));
    const videoIconBtn = allBtns.reverse().find((btn) => {
      const ariaLabel = (btn.getAttribute('aria-label') || '').toLowerCase();
      return ariaLabel.includes('video') && !ariaLabel.includes('make');
    });

    if (!videoIconBtn) {
      throw new Error('Video icon button not found.');
    }

    clickElement(videoIconBtn);
    await wait(1500);

    // Step V-2: Find video prompt input
    const videoEditableElement =
      document.querySelector(SELECTORS.promptInput) ||
      document.querySelector(SELECTORS.promptInputData) ||
      document.querySelector(SELECTORS.contentEditable);

    if (!videoEditableElement) {
      throw new Error('Video prompt input box not found.');
    }

    clickElement(videoEditableElement);
    videoEditableElement.focus();
    await wait(500);

    // Step V-3: Enter video prompt
    videoEditableElement.textContent = videoPromptText;
    videoEditableElement.dispatchEvent(new Event('input', { bubbles: true }));
    videoEditableElement.dispatchEvent(new Event('change', { bubbles: true }));
    await wait(500);

    // Step V-4: Submit
    const allBtnsV = Array.from(document.querySelectorAll('button'));
    const videoSubmitBtn = allBtnsV.reverse().find((b) => {
      const rect = b.getBoundingClientRect();
      return (
        rect.width > 0 &&
        rect.height > 0 &&
        (b.getAttribute('aria-label') === 'Make video' ||
          b.getAttribute('aria-label') === 'Edit' ||
          b.getAttribute('aria-label') === 'Grok' ||
          b.getAttribute('aria-label') === 'Send')
      );
    });

    if (!videoSubmitBtn) {
      throw new Error('Video submit button not found.');
    }

    const oldVideoUrl = window.location.href;
    clickElement(videoSubmitBtn);
    console.log('⏳ [Grok v5] Custom video prompt submitted. Waiting for URL change...');
    const urlResult = await waitForUrlChange(oldVideoUrl);
    return { mode: 'custom_video_prompt', postUrl, ...urlResult };
  }

  // ── Default Make Video Mode ──
  return triggerDefaultMakeVideo(postUrl);
}

async function triggerDefaultMakeVideo(postUrl) {
  console.log('🔎 [Grok v5] Default Make video mode...');
  const btn = findVisibleMakeVideoButton();

  if (!btn) {
    throw new Error("'Make video' button not found.");
  }

  const oldUrl = window.location.href;
  clickElement(btn);
  console.log('⏳ [Grok v5] Make video clicked. Waiting for URL change...');
  const urlResult = await waitForUrlChange(oldUrl);
  return { mode: 'default_make_video', postUrl, ...urlResult };
}

async function waitForUrlChange(oldUrl) {
  for (let i = 0; i < POLLING.urlChangeMaxAttempts; i++) {
    await wait(POLLING.urlChangeIntervalMs);
    if (window.location.href !== oldUrl) {
      console.log(`✅ [Grok v5] URL changed: ${window.location.href}`);
      return { videoUrl: window.location.href, urlChanged: true };
    }
  }
  console.warn('⚠️ [Grok v5] URL did not change. Continuing on current page...');
  return { videoUrl: window.location.href, urlChanged: false };
}

const isVideoGenerating = () => {
  const generatingEl = document.evaluate(
    "//div[.//span[contains(text(),'Generating')]]",
    document,
    null,
    XPathResult.FIRST_ORDERED_NODE_TYPE,
    null
  ).singleNodeValue;

  const cancelBtn = document.evaluate(
    "//button[normalize-space()='Cancel Video']",
    document,
    null,
    XPathResult.FIRST_ORDERED_NODE_TYPE,
    null
  ).singleNodeValue;

  return { generating: !!(generatingEl || cancelBtn), generatingEl, cancelBtn };
};

// ─────────────────────────────────────────────────────────────
// PHASE 3: VIDEO COMPLETION VERIFICATION
// ─────────────────────────────────────────────────────────────
async function checkVideoCompletion() {
  console.log('⏳ [Grok v5] Polling for video generation completion...');

  // Initial delay before checking generating indicator
  await wait(3000);

  for (let i = 0; i < POLLING.videoCompletionMaxAttempts; i++) {
    await wait(POLLING.videoCompletionIntervalMs);

    const { generating } = isVideoGenerating();

    // As long as generating indicator is visible, video is still generating
    if (generating) {
      if (i % 10 === 0) {
        console.log(`⏳ [Grok v5] Video still generating... attempt ${i + 1}/${POLLING.videoCompletionMaxAttempts}`);
      }
      continue;
    }

    // Generating indicator disappeared — check moderation FIRST, then success, then text patterns
    const moderation = detectModeration();
    if (moderation.moderated) {
      console.warn(`⚠️ [Grok v5] Generation moderated: ${moderation.reason}`);
      return { status: 'video_warning', error: `Generation moderated: ${moderation.reason}`, videoUrl: window.location.href };
    }

    const success = detectVideoSuccess();
    if (success.success) {
      console.log(`✅ [Grok v5] Video generation complete! ${success.videoUrl}`);
      return { status: 'completed', videoUrl: success.videoUrl };
    }

    const failure = detectVideoFailure();
    if (failure.failed) {
      console.warn(`❌ [Grok v5] Video generation failed: ${failure.reason}`);
      return { status: 'video_warning', error: `Video generation failed: ${failure.reason}`, videoUrl: window.location.href };
    }

    console.warn(`⚠️ [Grok v5] Generation indicator disappeared but no success/failure/moderation detected.`);
    // Continue polling in case page is still transitioning
  }

  console.warn('⚠️ [Grok v5] Video generation polling timed out.');
  return { status: 'video_warning', error: 'Video generation timed out after ~6 minutes.', videoUrl: window.location.href };
}

// ─────────────────────────────────────────────────────────────
// MAIN ORCHESTRATOR
// ─────────────────────────────────────────────────────────────
/**
 * @param {Object} options
 * @param {string} options.promptText - Image generation prompt
 * @param {string} options.thumbnailId - Thumbnail ID for targeted click
 * @param {string|null} options.videoPromptText - Custom video prompt (null for default/spicy)
 * @param {string|null} options.videoType - 'spicy' or null
 * @param {boolean} options.skipImageGeneration - Skip image phase (retry mode)
 * @param {string|null} options.postUrl - Existing post URL for retry mode
 * @returns {Promise<{status, videoUrl, postUrl, error, mode}>}
 */
async function automateGrokGeneration(options) {
  const {
    promptText = '',
    thumbnailId = '',
    videoPromptText = null,
    videoType = null,
    skipImageGeneration = false,
    postUrl = null,
  } = options;

  // Determine mode
  let mode = 'default_make_video';
  const hasVideoPrompt = typeof videoPromptText === 'string' && videoPromptText.trim().length > 0;
  const isSpicy = videoType === 'spicy';

  if (hasVideoPrompt) {
    mode = 'custom_video_prompt';
  } else if (isSpicy) {
    mode = 'spicy';
  }

  console.log(`🚀 [Grok v5] Mode: ${mode} | skipImage: ${skipImageGeneration}`);

  try {
    let currentPostUrl = postUrl || window.location.href;

    // ── PHASE 1: Image Generation ──
    if (!skipImageGeneration) {
      const imgResult = await runImageGeneration(promptText);
      currentPostUrl = imgResult.postUrl;
    }

    // ── PHASE 2: Trigger Video ──
    const triggerResult = await triggerVideoGeneration(
      mode,
      videoPromptText,
      videoType
    );

    // ── PHASE 3: Brief confirmation poll ──
    console.log('⏳ [Grok v5] Confirming video generation started...');
    await wait(3000);

    let generationConfirmed = false;
    const confirmationMaxAttempts = 20; // ~40 seconds
    const confirmationIntervalMs = 2000;

    for (let i = 0; i < confirmationMaxAttempts; i++) {
      const { generating } = isVideoGenerating();
      if (generating) {
        generationConfirmed = true;
        console.log('✅ [Grok v5] Video generation confirmed in progress.');
        break;
      }
      if (i % 5 === 0) {
        console.log(`⏳ [Grok v5] Waiting for generation indicator... attempt ${i + 1}/${confirmationMaxAttempts}`);
      }
      await wait(confirmationIntervalMs);
    }

    if (!generationConfirmed) {
      console.warn('⚠️ [Grok v5] Video generation did not start within confirmation window.');
      return {
        status: 'video_warning',
        error: 'Video generation did not start',
        videoUrl: triggerResult.videoUrl,
        postUrl: triggerResult.postUrl || currentPostUrl,
        mode: triggerResult.mode || mode,
      };
    }

    return {
      status: 'ok',
      videoUrl: triggerResult.videoUrl,
      postUrl: triggerResult.postUrl || currentPostUrl,
      error: null,
      mode: triggerResult.mode || mode,
    };
  } catch (err) {
    if (err.message.startsWith('IMAGE_MODERATED:')) {
      console.warn(`⚠️ [Grok v5] Image moderated during generation: ${err.message}`);
      return {
        status: 'image_warning',
        videoUrl: null,
        postUrl: window.location.href,
        error: err.message,
        mode,
      };
    }
    if (err.message.startsWith('IMAGE_GENERATION_TIMEOUT:')) {
      console.warn(`⚠️ [Grok v5] Image generation timeout: ${err.message}`);
      return {
        status: 'image_warning',
        videoUrl: null,
        postUrl: window.location.href,
        error: err.message,
        mode,
      };
    }
    console.warn('⚠️ [Grok v5] Fatal error, treating as image_warning:', err);
    return {
      status: 'image_warning',
      videoUrl: null,
      postUrl: window.location.href,
      error: err.message,
      mode,
    };
  }
}


// Export for module environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { automateGrokGeneration, checkVideoCompletion };
}
