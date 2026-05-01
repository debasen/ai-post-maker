---
description: Independent-step automation for generating videos on Grok. Each run handles one pending record end-to-end with inline retries. Requires --project <3> argument.
---

## Overview

Each run is **fully independent** and processes exactly one `pending` record:

1. Gets the next pending record
2. Navigates to Grok Imagine
3. Generates images (with inline retry on moderation)
4. Generates video (with inline retry on moderation/failure)
5. Waits for video completion
6. Extends video if requested (with inline retry on moderation/failure)
7. Downloads the final video
8. Updates tracker with terminal status

**Terminal statuses**: `completed` | `partial` | `failed` | `video_failed`

| Status | Meaning | Download? |
|--------|---------|-----------|
| `completed` | Image + Video + Extend all succeeded | Yes |
| `partial` | Image + Video succeeded, Extend failed | Yes (main video) |
| `failed` | Image generation failed (even after retry) | No |
| `video_failed` | Video generation failed (even after retry) | No |

---

## Step 1: Get Next Pending Record

```bash
python3 scripts/py/grok_tracker_v3.py --project 3 get_next
```

**Extract**: `id`, `prompt`, `video_prompt`, `extend_prompt`

If returns `{"error": "No pending prompts"}` → **Exit**.

---

## Step 2: Navigate to Grok Imagine

Hardcoded URL — never depends on a previous run:

```
https://grok.com/imagine
```

Call `browseros_navigate_page` with this URL.

---

## Step 3: Generate Images

Prepend `scripts/js/grok_automation_v2.min.js`, then evaluate:

```javascript
(async () => {
  return await generateGrokImages("INSERT_PROMPT_HERE");
})();
```

**Return values**:
- `{ status: 'ok', postUrl }` → Go to Step 4
- `{ status: 'image_moderated', postUrl, error }` → **Tone down the prompt** and retry once immediately:
  ```javascript
  (async () => {
    return await generateGrokImages("INSERT_TONED_DOWN_PROMPT_HERE");
  })();
  ```
  - If retry returns `ok` → Go to Step 4
  - If retry returns `image_moderated` or `image_failed` → **Mark as failed** (Step 8A)
- `{ status: 'image_failed', postUrl, error }` → **Mark as failed** (Step 8A)

**Tone-down rule**: Ask the LLM to rewrite the prompt to be less explicit, remove suggestive clothing descriptions, and avoid terms that trigger moderation. Keep the core scene intact.

---

## Step 4: Trigger Video Generation

Prepend the JS file, then evaluate:

```javascript
(async () => {
  const mode = (VIDEO_PROMPT && VIDEO_PROMPT.trim()) ? 'custom_video_prompt' : 'default_make_video';
  return await triggerVideoGeneration(mode, VIDEO_PROMPT || null);
})();
```

**Return values**:
- `{ status: 'ok', videoUrl, postUrl, mode }` → Go to Step 5
- `{ status: 'image_failed', postUrl, error }` → **Mark as failed** (Step 8A) *(all images moderated even after Generate More)*
- `{ status: 'video_failed', postUrl, error }` → **Go to Step 4B (retry)**

### Step 4B: Video Retry (if video_prompt exists)

If `video_prompt` is present:
1. Generate a toned-down `video_prompt` (less explicit camera direction, softer wording)
2. Retry with:
   ```javascript
   (async () => {
     return await triggerVideoGeneration('custom_video_prompt', 'INSERT_TONED_DOWN_VIDEO_PROMPT');
   })();
   ```
3. If retry returns `ok` → Go to Step 5
4. If retry returns `video_failed` → **Mark as video_failed** (Step 8B)

If `video_prompt` is **not** present:
- **Mark as video_failed** (Step 8B) immediately — nothing to tone down.

---

## Step 5: Wait for Video Completion

Prepend the JS file, then evaluate:

```javascript
(async () => {
  return await checkVideoCompletion();
})();
```

**Return values**:
- `{ status: 'completed', videoUrl }` → Go to Step 6
- `{ status: 'video_moderated', videoUrl, error }` → **Go to Step 4B** (same retry logic)
- `{ status: 'video_failed', videoUrl, error }` → **Go to Step 4B** (same retry logic)

If Step 4B already exhausted its retry → **Mark as video_failed** (Step 8B).

---

## Step 6: Extend Video (if extend_prompt exists)

Skip this step entirely if `extend_prompt` is null or empty.

Prepend the JS file, then evaluate:

```javascript
(async () => {
  return await extendVideo("INSERT_EXTEND_PROMPT_HERE");
})();
```

**Return values**:
- `{ extendStatus: 'completed', videoUrl }` → **Mark as completed** (Step 8C)
- `{ extendStatus: 'extend_moderated', error }` → **Go to Step 6B (retry)**
- `{ extendStatus: 'extend_failed', error }` → **Go to Step 6B (retry)**

### Step 6B: Extend Retry (if extend_prompt exists)

If `extend_prompt` is present:
1. Generate a toned-down `extend_prompt`
2. Retry with:
   ```javascript
   (async () => {
     return await extendVideo("INSERT_TONED_DOWN_EXTEND_PROMPT");
   })();
   ```
3. If retry returns `completed` → **Mark as completed** (Step 8C)
4. If retry returns `extend_moderated` or `extend_failed` → **Mark as partial** (Step 8D)

If `extend_prompt` is **not** present:
- **Mark as partial** (Step 8D) immediately — nothing to tone down.

---

## Step 7: Download Final Video

Applies when final status will be `completed` or `partial`.

1. **Locate Download Button**:
   - Call `browseros_take_snapshot` on the active page.
   - Identify the interactive element with `aria-label="Download"`.

2. **Download the File**:
   - Call `browseros_download_file` with the identified element ID.
   - Set `path` to the project destination directory: `project-<N>/assets/current/`.

3. **Rename**:
   ```bash
   python3 scripts/py/grok_video_downloader_v3.py --project <N> process_download project-<N>/assets/current/ <ID>
   ```
   - This command finds the most-recent file in the destination directory and renames it to `<ID>.mp4`.

4. **Verify**:
   - Confirm the file exists at `project-<N>/assets/current/<ID>.mp4` with non-zero size.

---

## Step 8: Update Tracker (Terminal Status)

### 8A: Image Failed
```bash
python3 scripts/py/grok_tracker_v3.py --project 3 mark_failed <ID> "<POST_URL>"
```

### 8B: Video Failed
```bash
python3 scripts/py/grok_tracker_v3.py --project 3 mark_video_failed <ID> "<POST_URL>"
```

### 8C: Completed
```bash
python3 scripts/py/grok_tracker_v3.py --project 3 complete <ID> "<VIDEO_URL>" "<POST_URL>"
```

### 8D: Partial (extend failed, video available)
```bash
python3 scripts/py/grok_tracker_v3.py --project 3 mark_partial <ID> "<VIDEO_URL>" "<POST_URL>"
```

---

## Edge Cases Summary

| Scenario | Behavior |
|----------|----------|
| All 4 images moderated on first try | Tone down prompt, retry. If still moderated → `failed` |
| All 4 images moderated, Generate More clicked, still 0 valid | `failed` (returned from `triggerVideoGeneration`) |
| Video step fails but no `video_prompt` | No retry → `video_failed` |
| Extend step fails but no `extend_prompt` | No retry → `partial` |
| Video succeeds, extend fails | `partial` — download the main video |
| No pending records | Exit immediately |

---

## Full Inline JavaScript Example

```javascript
// Prepend scripts/js/grok_automation_v2.min.js before evaluating this:

(async () => {
  const prompt = "INSERT_PROMPT";
  const videoPrompt = INSERT_VIDEO_PROMPT_OR_NULL;
  const extendPrompt = INSERT_EXTEND_PROMPT_OR_NULL;

  // Step 3: Generate images
  let imgResult = await generateGrokImages(prompt);
  if (imgResult.status === 'image_moderated') {
    const tonedDownPrompt = "INSERT_TONED_DOWN_PROMPT";
    imgResult = await generateGrokImages(tonedDownPrompt);
  }
  if (imgResult.status !== 'ok') {
    return { finalStatus: 'failed', postUrl: imgResult.postUrl };
  }

  // Step 4: Trigger video
  const mode = (videoPrompt && videoPrompt.trim()) ? 'custom_video_prompt' : 'default_make_video';
  let videoResult = await triggerVideoGeneration(mode, videoPrompt);
  if (videoResult.status === 'video_failed' && videoPrompt) {
    const tonedDownVideoPrompt = "INSERT_TONED_DOWN_VIDEO_PROMPT";
    videoResult = await triggerVideoGeneration('custom_video_prompt', tonedDownVideoPrompt);
  }
  if (videoResult.status !== 'ok') {
    return { finalStatus: 'video_failed', postUrl: videoResult.postUrl };
  }

  // Step 5: Wait for completion
  let completion = await checkVideoCompletion();
  if (completion.status !== 'completed' && videoPrompt) {
    const tonedDownVideoPrompt = "INSERT_TONED_DOWN_VIDEO_PROMPT";
    const retryResult = await triggerVideoGeneration('custom_video_prompt', tonedDownVideoPrompt);
    if (retryResult.status !== 'ok') {
      return { finalStatus: 'video_failed', postUrl: retryResult.postUrl };
    }
    completion = await checkVideoCompletion();
  }
  if (completion.status !== 'completed') {
    return { finalStatus: 'video_failed', postUrl: completion.videoUrl };
  }

  // Step 6: Extend
  if (extendPrompt && extendPrompt.trim()) {
    let extendResult = await extendVideo(extendPrompt);
    if (extendResult.extendStatus !== 'completed') {
      const tonedDownExtend = "INSERT_TONED_DOWN_EXTEND_PROMPT";
      extendResult = await extendVideo(tonedDownExtend);
    }
    if (extendResult.extendStatus === 'completed') {
      return { finalStatus: 'completed', videoUrl: extendResult.videoUrl, postUrl: window.location.href };
    }
    return { finalStatus: 'partial', videoUrl: completion.videoUrl, postUrl: window.location.href };
  }

  return { finalStatus: 'completed', videoUrl: completion.videoUrl, postUrl: window.location.href };
})();
```
