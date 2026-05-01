/**
 * Grok Image-to-Video Automation Script (v2.1)
 *
 * Independent-step API:
 *   generateGrokImages(promptText)  → { status, postUrl, error }
 *   automateGrokGenerationV2(opts)  → { status, postUrl, error }
 *   triggerVideoGeneration(mode, videoPromptText) → { status, videoUrl, postUrl, mode, error }
 *   extendVideo(extendPromptText)   → { extendStatus, videoUrl, error }
 *   checkVideoCompletion()          → { status, videoUrl, error }
 */

// ─────────────────────────────────────────────────────────────
// SELECTORS & CONFIG
// ─────────────────────────────────────────────────────────────
const SELECTORS = {
  promptInput: '[placeholder="Type to imagine"]',
  promptInputData: '[data-placeholder="Type to imagine"]',
  contentEditable: '[contenteditable="true"]',
  proseMirror: 'div[contenteditable="true"].ProseMirror',
  submitBtn: 'button[aria-label="Submit"], button[aria-label="Grok"], button[aria-label="Send"], button[aria-label="Edit"]',
  imageRadio: '[role="radio"]',
  makeVideoBtn: 'button[aria-label="Make video"]',
  moreOptionsBtn: 'button[aria-label="More options"]',
  extendMenuItem: "//*[@role='menuitem'][contains(., 'Extend')]",
  normalMenuItem: "//*[@role='menuitem'][contains(., 'Normal')]",
  downloadBtn: 'button[aria-label="Download"]',
  pauseBtn: 'button[aria-label="Pause"]',
  videoElement: 'video',
  eyeOffSvg: 'svg.lucide-eye-off',
  generateMoreBtn: "//button[contains(., 'Generate More')]",
  imageCard: 'div[class*="media-post-masonry-card"]',
  generatingIndicator: "//div[.//span[contains(text(),'Generating')]]",
  cancelVideoBtn: "//button[normalize-space()='Cancel Video']",
  spicyMenuItem: "//div[@role='menuitem']//div[normalize-space()='Spicy']",
  failurePatterns: [
    /moderated/i, /unable to generate/i, /failed/i, /restricted/i,
    /policy/i, /cannot create/i, /blocked/i, /content not available/i,
    /error generating/i,
  ],
};

const POLLING = {
  videoCompletionIntervalMs: 3000,
  videoCompletionMaxAttempts: 120,
  urlChangeIntervalMs: 2000,
  urlChangeMaxAttempts: 15,
  imageGenerationIntervalMs: 2000,
  imageGenerationMaxAttempts: 60,
  extendGenerationIntervalMs: 3000,
  extendGenerationMaxAttempts: 80,
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
  const candidates = btns.filter((b) => {
    const rect = b.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && !b.disabled && b.offsetParent !== null;
  });
  return candidates.length > 0 ? candidates[0] : null;
};

const detectVideoSuccess = () => {
  const video = document.querySelector(SELECTORS.videoElement);
  if (video && video.src && video.src.includes('.mp4')) {
    return { success: true, videoUrl: window.location.href };
  }
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

const isVideoGenerating = () => {
  const generatingEl = document.evaluate(
    SELECTORS.generatingIndicator, document, null,
    XPathResult.FIRST_ORDERED_NODE_TYPE, null
  ).singleNodeValue;

  const cancelBtn = document.evaluate(
    SELECTORS.cancelVideoBtn, document, null,
    XPathResult.FIRST_ORDERED_NODE_TYPE, null
  ).singleNodeValue;

  return { generating: !!(generatingEl || cancelBtn), generatingEl, cancelBtn };
};

// ─────────────────────────────────────────────────────────────
// HELPERS: GENERATION CONTROLS
// ─────────────────────────────────────────────────────────────

async function generateMoreImages() {
  console.log('📸 [Grok v2] Clicking "Generate More"...');
  const generateMoreBtn = document.evaluate(
    SELECTORS.generateMoreBtn, document, null,
    XPathResult.FIRST_ORDERED_NODE_TYPE, null
  ).singleNodeValue;

  if (generateMoreBtn) {
    clickElement(generateMoreBtn);
    await wait(3000);
    // Wait for at least one more image or timeout
    for (let i = 0; i < 30; i++) {
      await wait(2000);
      const cards = document.querySelectorAll(SELECTORS.imageCard);
      if (cards.length > 4) {
        console.log(`✅ [Grok v2] New images detected (${cards.length} total)`);
        return true;
      }
    }
  }
  return false;
}

// ─────────────────────────────────────────────────────────────
// STEP 1: IMAGE GENERATION (independent)
// ─────────────────────────────────────────────────────────────
async function generateGrokImages(promptText) {
  console.log('📸 [Grok v2] Starting image generation...');

  // Ensure Image mode is selected
  try {
    const radios = Array.from(document.querySelectorAll(SELECTORS.imageRadio));
    const imageRadio = radios.find((r) => r.textContent && r.textContent.includes('Image'));
    if (imageRadio) {
      const isChecked = imageRadio.getAttribute('aria-checked') === 'true';
      if (!isChecked) {
        clickElement(imageRadio);
        await wait(1000);
        console.log('📸 [Grok v2] Switched to Image mode');
      }
    }
  } catch (err) {
    console.warn('⚠️ [Grok v2] Could not verify Image mode:', err);
  }

  // Find input
  const editableElement =
    document.querySelector(SELECTORS.promptInput) ||
    document.querySelector(SELECTORS.promptInputData) ||
    document.querySelector(SELECTORS.contentEditable) ||
    document.querySelector(SELECTORS.proseMirror);

  if (!editableElement) {
    return { status: 'image_failed', postUrl: window.location.href, error: 'Prompt input box not found.' };
  }

  // Type prompt
  clickElement(editableElement);
  editableElement.focus();
  await wait(1000);

  editableElement.textContent = promptText;
  editableElement.dispatchEvent(new Event('input', { bubbles: true }));
  editableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(2000);

  // Submit
  const submitBtnSelectors = SELECTORS.submitBtn.split(', ');
  let submitBtn = null;
  for (const sel of submitBtnSelectors) {
    submitBtn = document.querySelector(sel);
    if (submitBtn) break;
  }
  if (!submitBtn) {
    return { status: 'image_failed', postUrl: window.location.href, error: 'Submit button not found.' };
  }

  submitBtn.click();
  console.log('⏳ [Grok v2] Image prompt submitted. Waiting for generation...');

  // Wait for image cards
  let generationStarted = false;
  for (let i = 0; i < POLLING.imageGenerationMaxAttempts; i++) {
    await wait(POLLING.imageGenerationIntervalMs);

    const { generating } = isVideoGenerating();
    if (generating) {
      generationStarted = true;
      if (i % 5 === 0) {
        console.log(`⏳ [Grok v2] Image generation in progress... attempt ${i + 1}/${POLLING.imageGenerationMaxAttempts}`);
      }
      continue;
    }

    // If we've seen it generating and now it's not, check for completion
    const cards = document.querySelectorAll(SELECTORS.imageCard);
    const hasMakeVideo = findVisibleMakeVideoButton();

    if (generationStarted || i > 5) { // Wait at least 10s if we didn't catch the generating state
      if (cards.length >= 4 || hasMakeVideo) {
        console.log('✅ [Grok v2] Image generation complete.');
        await wait(6000);
        return { status: 'ok', postUrl: window.location.href };
      }
    }

    const moderation = detectModeration();
    if (moderation.moderated) {
      console.warn(`⚠️ [Grok v2] Image moderated: ${moderation.reason}`);
      return { status: 'image_moderated', postUrl: window.location.href, error: moderation.reason };
    }

    if (i % 5 === 0) {
      console.log(`⏳ [Grok v2] Waiting for image generation... attempt ${i + 1}/${POLLING.imageGenerationMaxAttempts}`);
    }
  }

  return { status: 'image_failed', postUrl: window.location.href, error: 'Image generation timed out.' };
}

/**
 * Wrapper to match plan naming.
 */
async function automateGrokGenerationV2({ promptText, skipImageGeneration = false }) {
  if (skipImageGeneration) return { status: 'ok', postUrl: window.location.href };
  return await generateGrokImages(promptText);
}

// ─────────────────────────────────────────────────────────────
// STEP 2: SELECT BEST IMAGE (independent)
// ─────────────────────────────────────────────────────────────
async function selectBestImage() {
  console.log('📸 [Grok v2] Selecting best image...');

  // Wait for image cards to appear
  let cards = [];
  let attempts = 0;
  while (cards.length < 4 && attempts < POLLING.imageGenerationMaxAttempts) {
    await wait(POLLING.imageGenerationIntervalMs);
    cards = Array.from(document.querySelectorAll(SELECTORS.imageCard));
    attempts++;
  }

  if (cards.length === 0) {
    // Fallback: look for any img elements in masonry layout
    const allImgs = Array.from(document.querySelectorAll('img[src*="imagine-public"]'));
    if (allImgs.length >= 4) {
      cards = allImgs.slice(0, 4);
    }
  }

  console.log(`📸 [Grok v2] Found ${cards.length} image cards`);

  // Evaluate each card
  const validCards = [];
  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];
    const hasModeration = card.querySelector(SELECTORS.eyeOffSvg) !== null;
    if (hasModeration) {
      console.log(`⚠️ [Grok v2] Card ${i} is moderated, skipping`);
      continue;
    }
    validCards.push({ index: i, card });
  }

  console.log(`📸 [Grok v2] ${validCards.length} valid cards after moderation filter`);

  // If not enough valid images, try Generate More
  if (validCards.length < 2) {
    const success = await generateMoreImages();
    if (success) {
      // Re-evaluate
      const newCards = Array.from(document.querySelectorAll(SELECTORS.imageCard));
      validCards.length = 0;
      for (let i = 0; i < newCards.length; i++) {
        const card = newCards[i];
        const hasModeration = card.querySelector(SELECTORS.eyeOffSvg) !== null;
        if (!hasModeration) {
          validCards.push({ index: i, card });
        }
      }
    }
  }

  if (validCards.length === 0) {
    return { status: 'image_failed', error: 'No valid images after Generate More' };
  }

  // Select best image - prefer first valid as fallback
  const bestCard = validCards[0];
  console.log(`📸 [Grok v2] Selected card ${bestCard.index} (${validCards.length} valid options)`);

  // Click the selected card to enter detail view
  clickElement(bestCard.card);
  await wait(2000);

  return { status: 'ok', selectedIndex: bestCard.index, card: bestCard.card, totalValid: validCards.length };
}

// ─────────────────────────────────────────────────────────────
// STEP 3: VIDEO GENERATION TRIGGER (independent)
// ─────────────────────────────────────────────────────────────
async function triggerVideoGeneration(mode, videoPromptText) {
  const postUrl = window.location.href;

  // First, select best image and enter detail view
  const selection = await selectBestImage();
  if (selection.status === 'image_failed') {
    return { status: 'image_failed', postUrl, error: selection.error };
  }

  // Spicy Mode
  if (mode === 'spicy') {
    console.log('🌶️ [Grok v2] Spicy mode...');
    const allBtns = Array.from(document.querySelectorAll('button'));
    const moreOptionsBtn = allBtns.find((b) => {
      const label = (b.getAttribute('aria-label') || '').toLowerCase();
      return label.includes('more options') || label.includes('more');
    });

    if (!moreOptionsBtn) {
      console.warn("⚠️ [Grok v2] 'More options' not found. Falling back to default.");
      return triggerDefaultMakeVideo(postUrl);
    }

    if (moreOptionsBtn.getAttribute('aria-expanded') !== 'true') {
      clickElement(moreOptionsBtn);
      await wait(1500);
    }

    let spicyBtn = null;
    try {
      spicyBtn = document.evaluate(
        SELECTORS.spicyMenuItem, document, null,
        XPathResult.FIRST_ORDERED_NODE_TYPE, null
      ).singleNodeValue;
    } catch (e) { }

    if (!spicyBtn) {
      const menuItems = Array.from(document.querySelectorAll('[role="menuitem"]'));
      spicyBtn = menuItems.find((el) => el.textContent && el.textContent.includes('Spicy'));
    }

    if (!spicyBtn) {
      console.warn("⚠️ [Grok v2] 'Spicy' not found. Falling back to default.");
      document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      await wait(1000);
      return triggerDefaultMakeVideo(postUrl);
    }

    const oldUrl = window.location.href;
    clickElement(spicyBtn);
    console.log('⏳ [Grok v2] Spicy clicked. Waiting for URL change...');
    const urlResult = await waitForUrlChange(oldUrl);
    return { status: 'ok', mode: 'spicy', postUrl, ...urlResult };
  }

  // Custom Video Prompt Mode
  if (mode === 'custom_video_prompt') {
    console.log('🎬 [Grok v2] Custom video prompt mode...');

    // Find video prompt input
    const videoEditableElement =
      document.querySelector(SELECTORS.promptInput) ||
      document.querySelector(SELECTORS.promptInputData) ||
      document.querySelector(SELECTORS.contentEditable) ||
      document.querySelector(SELECTORS.proseMirror);

    if (!videoEditableElement) {
      return { status: 'video_failed', postUrl, error: 'Video prompt input box not found.' };
    }

    clickElement(videoEditableElement);
    videoEditableElement.focus();
    await wait(500);

    videoEditableElement.textContent = videoPromptText;
    videoEditableElement.dispatchEvent(new Event('input', { bubbles: true }));
    videoEditableElement.dispatchEvent(new Event('change', { bubbles: true }));
    await wait(500);

    // Find submit button
    const allBtnsV = Array.from(document.querySelectorAll('button'));
    const videoSubmitBtn = allBtnsV.reverse().find((b) => {
      const rect = b.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 &&
        ['Submit', 'Make video', 'Edit', 'Grok', 'Send'].includes(b.getAttribute('aria-label') || '');
    });

    if (!videoSubmitBtn) {
      return { status: 'video_failed', postUrl, error: 'Video submit button not found.' };
    }

    const oldVideoUrl = window.location.href;
    clickElement(videoSubmitBtn);
    console.log('⏳ [Grok v2] Custom video prompt submitted. Waiting...');
    const urlResult = await waitForUrlChange(oldVideoUrl);
    return { status: 'ok', mode: 'custom_video_prompt', postUrl, ...urlResult };
  }

  // Default Make Video Mode
  return triggerDefaultMakeVideo(postUrl);
}

async function triggerDefaultMakeVideo(postUrl) {
  console.log('🔎 [Grok v2] Default Make video mode...');

  const btn = findVisibleMakeVideoButton();
  if (!btn) {
    return { status: 'video_failed', postUrl, error: "'Make video' button not found in detail view." };
  }

  const oldUrl = window.location.href;
  clickElement(btn);
  console.log('⏳ [Grok v2] Make video clicked. Waiting for URL change...');
  const urlResult = await waitForUrlChange(oldUrl);
  return { status: 'ok', mode: 'default_make_video', postUrl, selectedIndex: 0, ...urlResult };
}

async function waitForUrlChange(oldUrl) {
  for (let i = 0; i < POLLING.urlChangeMaxAttempts; i++) {
    await wait(POLLING.urlChangeIntervalMs);
    if (window.location.href !== oldUrl) {
      console.log(`✅ [Grok v2] URL changed: ${window.location.href}`);
      return { videoUrl: window.location.href, urlChanged: true };
    }
  }
  console.warn('⚠️ [Grok v2] URL did not change. Continuing on current page...');
  return { videoUrl: window.location.href, urlChanged: false };
}

// ─────────────────────────────────────────────────────────────
// STEP 4: VIDEO COMPLETION VERIFICATION (independent)
// ─────────────────────────────────────────────────────────────
async function checkVideoCompletion() {
  console.log('⏳ [Grok v2] Polling for video generation completion...');

  await wait(3000);

  for (let i = 0; i < POLLING.videoCompletionMaxAttempts; i++) {
    await wait(POLLING.videoCompletionIntervalMs);

    const { generating } = isVideoGenerating();
    if (generating) {
      if (i % 10 === 0) {
        console.log(`⏳ [Grok v2] Video still generating... attempt ${i + 1}/${POLLING.videoCompletionMaxAttempts}`);
      }
      continue;
    }

    const moderation = detectModeration();
    if (moderation.moderated) {
      console.warn(`⚠️ [Grok v2] Generation moderated: ${moderation.reason}`);
      return { status: 'video_moderated', error: `Generation moderated: ${moderation.reason}`, videoUrl: window.location.href };
    }

    const success = detectVideoSuccess();
    if (success.success) {
      console.log(`✅ [Grok v2] Video generation complete! ${success.videoUrl}`);
      return { status: 'completed', videoUrl: success.videoUrl };
    }

    const failure = detectVideoFailure();
    if (failure.failed) {
      console.warn(`❌ [Grok v2] Video generation failed: ${failure.reason}`);
      return { status: 'video_failed', error: `Video generation failed: ${failure.reason}`, videoUrl: window.location.href };
    }

    console.warn(`⚠️ [Grok v2] Generation indicator disappeared but no success/failure detected.`);
  }

  console.warn('⚠️ [Grok v2] Video generation polling timed out.');
  return { status: 'video_failed', error: 'Video generation timed out.', videoUrl: window.location.href };
}

// ─────────────────────────────────────────────────────────────
// STEP 5: EXTEND VIDEO (independent)
// ─────────────────────────────────────────────────────────────
async function extendVideo(extendPromptText) {
  console.log('➡️ [Grok v2] Starting video extension...');

  // Click More options
  const allBtns = Array.from(document.querySelectorAll('button'));
  const moreOptionsBtn = allBtns.find((b) => {
    const label = (b.getAttribute('aria-label') || '').toLowerCase();
    return label.includes('more options') || label.includes('more');
  });

  if (!moreOptionsBtn) {
    return { extendStatus: 'extend_failed', error: 'More options button not found' };
  }

  if (moreOptionsBtn.getAttribute('aria-expanded') !== 'true') {
    clickElement(moreOptionsBtn);
    await wait(1500);
  }

  // Find Extend menu item
  let extendBtn = null;
  try {
    extendBtn = document.evaluate(
      SELECTORS.extendMenuItem, document, null,
      XPathResult.FIRST_ORDERED_NODE_TYPE, null
    ).singleNodeValue;
  } catch (e) { }

  if (!extendBtn) {
    const menuItems = Array.from(document.querySelectorAll('[role="menuitem"]'));
    extendBtn = menuItems.find((el) => el.textContent && el.textContent.includes('Extend'));
  }

  if (!extendBtn) {
    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    return { extendStatus: 'extend_failed', error: 'Extend menu item not found' };
  }

  clickElement(extendBtn);
  await wait(2000);

  // Close menu if still open
  document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  await wait(500);

  // Find input and enter extend prompt
  const extendEditableElement =
    document.querySelector(SELECTORS.promptInput) ||
    document.querySelector(SELECTORS.promptInputData) ||
    document.querySelector(SELECTORS.contentEditable) ||
    document.querySelector(SELECTORS.proseMirror);

  if (!extendEditableElement) {
    return { extendStatus: 'extend_failed', error: 'Extend prompt input not found' };
  }

  clickElement(extendEditableElement);
  extendEditableElement.focus();
  await wait(500);

  extendEditableElement.textContent = extendPromptText;
  extendEditableElement.dispatchEvent(new Event('input', { bubbles: true }));
  extendEditableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(500);

  // Submit extend prompt
  const extendSubmitBtnSelectors = SELECTORS.submitBtn.split(', ');
  let extendSubmitBtn = null;
  for (const sel of extendSubmitBtnSelectors) {
    extendSubmitBtn = document.querySelector(sel);
    if (extendSubmitBtn) break;
  }
  if (!extendSubmitBtn) {
    return { extendStatus: 'extend_failed', error: 'Submit button not found for extend' };
  }

  clickElement(extendSubmitBtn);
  console.log('⏳ [Grok v2] Extend prompt submitted. Waiting for generation...');

  // Poll for extend completion
  for (let i = 0; i < POLLING.extendGenerationMaxAttempts; i++) {
    await wait(POLLING.extendGenerationIntervalMs);

    const { generating } = isVideoGenerating();
    if (!generating) {
      const moderation = detectModeration();
      if (moderation.moderated) {
        return { extendStatus: 'extend_moderated', error: `Extend moderated: ${moderation.reason}` };
      }

      const success = detectVideoSuccess();
      if (success.success) {
        console.log('✅ [Grok v2] Video extension complete!');
        return { extendStatus: 'completed', videoUrl: success.videoUrl };
      }

      const failure = detectVideoFailure();
      if (failure.failed) {
        return { extendStatus: 'extend_failed', error: `Extend failed: ${failure.reason}` };
      }
    }

    if (i % 10 === 0) {
      console.log(`⏳ [Grok v2] Extension still generating... attempt ${i + 1}/${POLLING.extendGenerationMaxAttempts}`);
    }
  }

  return { extendStatus: 'extend_failed', error: 'Extend generation timed out' };
}

// Export for module environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    generateGrokImages,
    automateGrokGenerationV2,
    selectBestImage,
    triggerVideoGeneration,
    checkVideoCompletion,
    extendVideo,
    generateMoreImages
  };
}
