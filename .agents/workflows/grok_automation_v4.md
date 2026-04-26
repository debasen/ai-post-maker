---
name: Grok Video Generation Automation (Advanced)
description: Advanced end-to-end automation skill for generating videos on Grok. Works for both project-1 and project-2. Supports two video generation paths — (A) custom video prompt via the 4-step UI flow when `video_prompt` is present in the prompt entry, or (B) the default "Make video" button click. Requires --project <1|2> argument.
---

## Overview

This workflow has two video generation paths that are selected automatically based on the data:

| Mode | Trigger | Description |
|------|---------|-------------|
| **Custom Video Prompt** | `video_prompt` field present in prompt entry | Clicks the Video icon (Step-1), enters the video prompt into the input box (Steps 2–3), and submits (Step-4) |
| **Default Make Video** | No `video_prompt` field | Waits for the "Make video" button to appear after image generation and clicks it |

---

### Step 0: Identify the Project
Determine which project to run for. The user will specify `--project 1` or `--project 2`. All commands below use this value.

---

### Step 1: Pick the Next Pending Prompt
Run the following command to get the next pending prompt:
```bash
python3 shared/grok_tracker.py --project <N> get_next
```
Extract the `id`, `prompt`, `instagram_caption`, and — if present — `video_prompt` from the output JSON.

> **Note**: If the returned entry has a `video_prompt` field (non-null, non-empty string), use **Custom Video Prompt Mode** (4-step UI flow). Otherwise, use the **Default Make Video Mode**.

---

### Step 2: Read Project Config (Starting URL)
Run the following command to get the project-specific Grok starting URL:
```bash
python3 shared/grok_tracker.py --project <N> get_config
```
This returns:
```json
{
  "starting_url": "https://grok.com/imagine/post/<post-id>",
  "thumbnail_id": "<post-id>"
}
```
Use `starting_url` as the navigation target in Step 3 and `thumbnail_id` in the JS automation script in Step 4.

---

### Step 3: Ensure Browser Context
- Ensure you have a browser window active on Grok at the `starting_url` returned above.
- If not already on the correct interface, navigate there using the `navigate_page` tool from the browseros MCP.

---

### Step 4: Execute Unified Automation Script

Inject and evaluate the following asynchronous JavaScript snippet into the active Grok tab using the `evaluate_script` tool from the browseros MCP.

Substitute the following placeholders:
- `PROMPT_TEXT` → `prompt` from Step 1
- `THUMBNAIL_ID` → `thumbnail_id` from Step 2
- `VIDEO_PROMPT_TEXT` → `video_prompt` from Step 1 (use `null` or empty string `""` if not present, to trigger the default Make Video path)

```javascript
/**
 * Executes the advanced Grok Image-to-Video DOM automation sequence.
 *
 * @param {string} promptText       The image generation prompt to submit.
 * @param {string} thumbnailId      The image post ID to target for thumbnail click.
 * @param {string|null} videoPromptText  (Optional) If provided, uses the 4-step custom video
 *                                       prompt UI flow instead of clicking "Make video".
 * @returns {Promise<Object>} { success, videoUrl, postUrl, mode, warning?, error? }
 */
async function automateGrokGenerationAdvanced(promptText, thumbnailId, videoPromptText) {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  const hasVideoPrompt = typeof videoPromptText === 'string' && videoPromptText.trim().length > 0;

  console.log("🚀 [Grok Automation v4] Starting sequence...");
  console.log(`🎬 [Grok Automation v4] Mode: ${hasVideoPrompt ? 'Custom Video Prompt (4-step UI)' : 'Default Make Video'}`);

  // ─────────────────────────────────────────────────────────────
  // PHASE 1: Image Generation (same for both modes)
  // ─────────────────────────────────────────────────────────────

  // Step 1A: Click the target thumbnail to open the image view
  try {
    const postIdMatch = window.location.href.match(/post\/([a-f0-9\-]+)/);
    if (postIdMatch) {
      console.log("📸 [Grok Automation v4] Detected post URL, attempting to click targeted thumbnail...");
      const img = document.querySelector(`img[src*="${thumbnailId}"]`);
      if (img) {
        img.click();
        await wait(2000);
      } else {
        console.warn(`⚠️ [Grok Automation v4] Thumbnail with ID ${thumbnailId} not found.`);
      }
    } else {
      console.log("📸 [Grok Automation v4] Not on a specific post. Clicking first available image if present.");
      const imgs = document.querySelectorAll('img');
      if (imgs.length > 0) {
        imgs[0].click();
        await wait(2000);
      }
    }
  } catch (err) {
    console.error("❌ [Grok Automation v4] Error in phase 1 (thumbnail click):", err);
  }

  // Step 1B: Locate the image generation prompt input box
  console.log("📝 [Grok Automation v4] Locating image prompt input box...");
  const editableElement = document.querySelector('[placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[data-placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[contenteditable="true"]');

  if (!editableElement) {
    console.error("❌ [Grok Automation v4] Prompt input box not found!");
    return { error: "Prompt input box not found. Make sure you are on a valid image edit view or chat." };
  }

  editableElement.click();
  editableElement.focus();
  await wait(500);

  // Step 1C: Inject the image prompt text
  console.log("✍️ [Grok Automation v4] Injecting image prompt text...");
  editableElement.textContent = promptText;
  editableElement.dispatchEvent(new Event('input', { bubbles: true }));
  editableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(500);

  // Step 1D: Click Submit (image generation)
  console.log("▶️ [Grok Automation v4] Submitting image prompt...");
  let submitBtn = document.querySelector('button[aria-label="Edit"]') ||
                  document.querySelector('button[aria-label="Grok"]') ||
                  document.querySelector('button[aria-label="Send"]');

  if (!submitBtn) {
    const buttons = Array.from(document.querySelectorAll('button'));
    submitBtn = buttons.reverse().find(b => {
      const rect = b.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
  }

  if (!submitBtn) {
    console.error("❌ [Grok Automation v4] Submit button not found!");
    return { error: "Submit button not found." };
  }

  submitBtn.click();
  console.log("⏳ [Grok Automation v4] Image prompt submitted. Waiting for image generation...");

  // ─────────────────────────────────────────────────────────────
  // PHASE 2A: DEFAULT MODE — Poll for 'Make video' button
  // ─────────────────────────────────────────────────────────────
  if (!hasVideoPrompt) {
    console.log("🔎 [Grok Automation v4] [Default Mode] Polling for 'Make video' button...");
    let makeVideoBtn = null;
    for (let i = 0; i < 60; i++) { // wait up to 120s
      await wait(2000);
      const buttons = Array.from(document.querySelectorAll('button'));
      makeVideoBtn = buttons.find(btn =>
        (btn.textContent && btn.textContent.includes('Make video')) ||
        btn.getAttribute('aria-label') === 'Make video'
      );

      if (makeVideoBtn) {
        console.log("✅ [Grok Automation v4] 'Make video' button found!");
        break;
      }
      if (i % 5 === 0) console.log(`⏳ [Grok Automation v4] Polling... attempt ${i + 1}/60`);
    }

    if (!makeVideoBtn) {
      console.error("❌ [Grok Automation v4] 'Make video' button did not appear.");
      return { error: "'Make video' button did not appear. Generation may have timed out or failed." };
    }

    const postUrl = window.location.href;

    console.log("🎥 [Grok Automation v4] Clicking 'Make video'...");
    const oldUrl = window.location.href;
    makeVideoBtn.click();
    console.log("⏳ [Grok Automation v4] Waiting for URL propagation to video job...");

    for (let i = 0; i < 15; i++) { // Poll for up to 30s
      await wait(2000);
      if (window.location.href !== oldUrl) {
        console.log(`✅ [Grok Automation v4] Success! Video URL: ${window.location.href}`);
        return { success: true, mode: 'default_make_video', videoUrl: window.location.href, postUrl };
      }
    }

    console.warn("⚠️ [Grok Automation v4] URL did not change after clicking 'Make video'. Assumed started.");
    return {
      success: true,
      mode: 'default_make_video',
      videoUrl: window.location.href,
      postUrl,
      warning: "URL did not change, but 'Make video' workflow concluded."
    };
  }

  // ─────────────────────────────────────────────────────────────
  // PHASE 2B: CUSTOM VIDEO PROMPT MODE — 4-Step UI Flow
  // ─────────────────────────────────────────────────────────────

  // Wait for image generation to complete (poll for the image / video icon to appear)
  console.log("🔎 [Grok Automation v4] [Custom Prompt Mode] Waiting for generated image before triggering video flow...");
  await wait(4000); // Initial buffer for generation to kick off

  // Poll until the image appears (up to 120s)
  let imageReady = false;
  for (let i = 0; i < 60; i++) {
    await wait(2000);
    // Check if a generated image is present in the result area (not thumbnails)
    const resultImgs = document.querySelectorAll('img[src*="grok"]');
    if (resultImgs.length > 0) {
      imageReady = true;
      console.log("✅ [Grok Automation v4] Generated image detected.");
      break;
    }
    if (i % 5 === 0) console.log(`⏳ [Grok Automation v4] Waiting for image... attempt ${i + 1}/60`);
  }

  if (!imageReady) {
    console.warn("⚠️ [Grok Automation v4] Could not confirm image generation, proceeding anyway...");
  }

  const postUrl = window.location.href;
  await wait(1000);

  // ── Step V-1: Click the Video Icon button ────────────────────
  console.log("🎬 [Grok Automation v4] [Step V-1] Clicking the Video icon button...");
  let videoIconBtn = document.querySelector('button[aria-label="Video"]');

  if (!videoIconBtn) {
    // Fallback: look for a button containing a video camera SVG icon
    const allBtns = Array.from(document.querySelectorAll('button'));
    videoIconBtn = allBtns.find(btn => {
      const ariaLabel = (btn.getAttribute('aria-label') || '').toLowerCase();
      return ariaLabel.includes('video') && !ariaLabel.includes('make');
    });
  }

  if (!videoIconBtn) {
    console.error("❌ [Grok Automation v4] Video icon button not found!");
    return { error: "Video icon button not found. The generated image may not have appeared or the UI changed." };
  }

  videoIconBtn.click();
  console.log("⏳ [Grok Automation v4] Clicked Video icon. Waiting for video prompt input to appear...");
  await wait(1500);

  // ── Step V-2: Locate the Video Prompt Input Box ──────────────
  console.log("📝 [Grok Automation v4] [Step V-2] Locating video prompt input box...");
  const videoEditableElement =
    document.querySelector('[placeholder="Describe your edit, @ to reference images"]') ||
    document.querySelector('[data-placeholder="Describe your edit, @ to reference images"]') ||
    document.querySelector('[contenteditable="true"]');

  if (!videoEditableElement) {
    console.error("❌ [Grok Automation v4] Video prompt input box not found after clicking Video icon!");
    return { error: "Video prompt input box not found. Make sure the video editing panel opened." };
  }

  videoEditableElement.click();
  videoEditableElement.focus();
  await wait(500);

  // ── Step V-3: Enter the Video Prompt ─────────────────────────
  console.log(`✍️ [Grok Automation v4] [Step V-3] Entering video prompt: "${videoPromptText.substring(0, 80)}..."`);
  videoEditableElement.textContent = videoPromptText;
  videoEditableElement.dispatchEvent(new Event('input', { bubbles: true }));
  videoEditableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(500);

  // ── Step V-4: Submit the Video Prompt ────────────────────────
  console.log("▶️ [Grok Automation v4] [Step V-4] Submitting video prompt...");
  let videoSubmitBtn =
    document.querySelector('button[aria-label="Make video"]') ||
    document.querySelector('button[aria-label="Edit"]') ||
    document.querySelector('button[aria-label="Grok"]') ||
    document.querySelector('button[aria-label="Send"]');

  if (!videoSubmitBtn) {
    // Generic fallback: last visible button (same as image submit)
    const buttons = Array.from(document.querySelectorAll('button'));
    videoSubmitBtn = buttons.reverse().find(b => {
      const rect = b.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
  }

  if (!videoSubmitBtn) {
    console.error("❌ [Grok Automation v4] Video submit button not found!");
    return { error: "Video submit button not found." };
  }

  const oldVideoUrl = window.location.href;
  videoSubmitBtn.click();
  console.log("⏳ [Grok Automation v4] Video prompt submitted. Waiting for URL propagation to video job...");

  // Poll for URL change (up to 30s)
  for (let i = 0; i < 15; i++) {
    await wait(2000);
    if (window.location.href !== oldVideoUrl) {
      console.log(`✅ [Grok Automation v4] Success! Video URL: ${window.location.href}`);
      return { success: true, mode: 'custom_video_prompt', videoUrl: window.location.href, postUrl };
    }
  }

  console.warn("⚠️ [Grok Automation v4] URL did not change after submitting video prompt. Assumed started.");
  return {
    success: true,
    mode: 'custom_video_prompt',
    videoUrl: window.location.href,
    postUrl,
    warning: "URL did not change, but custom video prompt workflow concluded."
  };
}

// ── Usage ────────────────────────────────────────────────────────────────────
// Default Make Video mode (no video_prompt):
//   return await automateGrokGenerationAdvanced("PROMPT_TEXT", "THUMBNAIL_ID", null);
//
// Custom Video Prompt mode (video_prompt present):
//   return await automateGrokGenerationAdvanced("PROMPT_TEXT", "THUMBNAIL_ID", "VIDEO_PROMPT_TEXT");
```

---

### Step 5: Determine Mode and Handle Result

After the script returns, inspect the `mode` field:

- `mode: "default_make_video"` → Standard flow completed. Proceed normally.
- `mode: "custom_video_prompt"` → Custom 4-step flow completed. Proceed normally.

If the result contains `error`, investigate the console logs and retry if appropriate.

---

### Step 6: Update the Tracker
Once the script successfully executes and returns `{ success: true, videoUrl: "...", postUrl: "..." }`:
1. Run the update command using the `id` from Step 1:
   ```bash
   python3 shared/grok_tracker.py --project <N> complete <ID> "<VIDEO_URL>" "<POST_URL>"
   ```
2. Verify the script returns a success JSON.

---

## Data Schema Reference

### Prompt Entry with Default Mode (no `video_prompt`):
```json
{
  "id": 42,
  "prompt": "Imagine the exact model ...",
  "status": "pending",
  "instagram_caption": "...",
  "video_url": null,
  "post_url": null,
  "executed_at": null
}
```

### Prompt Entry with Custom Video Prompt Mode:
```json
{
  "id": 43,
  "prompt": "Imagine the exact model ...",
  "video_prompt": "Camera slowly pans upward as the model gazes at the horizon, cinematic lighting, wind gently moving hair",
  "status": "pending",
  "instagram_caption": "...",
  "video_url": null,
  "post_url": null,
  "executed_at": null
}
```

> When `video_prompt` is present and non-empty, the 4-step custom video UI flow is automatically activated.
