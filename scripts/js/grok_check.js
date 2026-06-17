/**
 * Grok Video Completion Checker (extracted from grok_automation.js)
 *
 * Usage: Inject via evaluate_script, then call:
 *   await checkVideoCompletion();
 *
 * Returns: { status: 'completed'|'video_warning', videoUrl, error }
 */

const SELECTORS = {
  videoElement: 'video',
  pauseBtn: 'button[aria-label="Pause"]',
  downloadBtn: 'button[aria-label="Download"]',
  eyeOffSvg: 'svg.lucide-eye-off',
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
  videoCompletionMaxAttempts: 120,
};

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
  const generatingEl = Array.from(document.querySelectorAll('div')).find(el => {
    const span = el.querySelector('span');
    if (span && span.textContent.includes('Generating')) {
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && el.offsetParent !== null;
    }
    return false;
  });

  const cancelBtn = Array.from(document.querySelectorAll('button')).find(btn => {
    const text = btn.textContent.trim();
    if (text === 'Cancel' || text === 'Cancel Video') {
      const rect = btn.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && btn.offsetParent !== null;
    }
    return false;
  });

  const hasProgress = document.body && (
    document.body.innerText.includes('Generating') && /\b\d+%\b/.test(document.body.innerText)
  );

  return { generating: !!(generatingEl || cancelBtn || hasProgress), generatingEl, cancelBtn };
};

async function checkVideoCompletion() {
  console.log('[GrokCheck] Polling for video generation completion...');

  await wait(3000);

  for (let i = 0; i < POLLING.videoCompletionMaxAttempts; i++) {
    await wait(POLLING.videoCompletionIntervalMs);

    const { generating } = isVideoGenerating();

    if (generating) {
      if (i % 10 === 0) {
        console.log(`[GrokCheck] Video still generating... attempt ${i + 1}/${POLLING.videoCompletionMaxAttempts}`);
      }
      continue;
    }

    const moderation = detectModeration();
    if (moderation.moderated) {
      console.warn(`[GrokCheck] Generation moderated: ${moderation.reason}`);
      return { status: 'video_warning', error: `Generation moderated: ${moderation.reason}`, videoUrl: window.location.href };
    }

    const success = detectVideoSuccess();
    if (success.success) {
      console.log(`[GrokCheck] Video generation complete! ${success.videoUrl}`);
      return { status: 'completed', videoUrl: success.videoUrl };
    }

    const failure = detectVideoFailure();
    if (failure.failed) {
      console.warn(`[GrokCheck] Video generation failed: ${failure.reason}`);
      return { status: 'video_warning', error: `Video generation failed: ${failure.reason}`, videoUrl: window.location.href };
    }

    console.warn(`[GrokCheck] Generation indicator disappeared but no success/failure/moderation detected.`);
  }

  console.warn('[GrokCheck] Video generation polling timed out.');
  return { status: 'video_warning', error: 'Video generation timed out after ~6 minutes.', videoUrl: window.location.href };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { checkVideoCompletion };
}
