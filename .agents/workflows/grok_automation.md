---
description: Advanced end-to-end automation skill for generating videos on Grok. Requires --project <1|2> argument. Supports retry for video_failed items.
---

## Overview

This workflow automates Grok image-to-video generation with **completion verification** and **retry logic**.

### Status Lifecycle

| Status | Meaning | Next Action |
|--------|---------|-------------|
| `pending` | New item, never processed | Full flow: image generation → video generation → verify completion |
| `video_warning` | Video moderated/failed/timed out on **first** attempt | Retry: skip image generation, use default "Make video" |
| `image_warning` | Image moderated on **first** attempt | Retry: skip image generation, use default "Make video" |
| `video_failed` | Second video failure or fatal error (terminal) | Never retried |
| `image_failed` | Second image failure or fatal error (terminal) | Never retried |
| `failed` | Fatal script error (terminal) | Never retried |
| `completed` | Video successfully generated | Ready for mapping |

### Video Generation Modes

| Mode | Trigger | Description |
|------|---------|-------------|
| **Custom Video Prompt** | `video_prompt` field present | 4-step UI flow: Video icon → prompt → submit |
| **Spicy Video** | `video_type` is `spicy` | Clicks three dots menu → "Spicy" |
| **Default Make Video** | No `video_prompt`, no `video_type: spicy` | Clicks "Make video" button after image generation |

> **Retry Rule**: When processing a `video_failed` item, all modes fall back to **Default Make Video** (custom prompt and spicy are stripped).

---

## Step 0: Identify the Project

The user specifies `--project 1` or `--project 2`. All commands below use this value.

---

## Step 1: Pick the Next Pending or Retry Prompt

```bash
python3 shared/grok_tracker.py --project <N> get_next
```

Extract fields from the output JSON:
- `id`, `prompt`, `instagram_caption`
- `video_prompt` (if present)
- `video_type` (if present)
- `post_url` (present on retry items)
- `retry_mode`: `true` for `video_warning`/`image_warning`, `false` for `pending` and terminal states
- `retry_reason`: indicates why retry is needed (`video_warning`, `image_warning`)

If `retry_mode` is `true`, proceed to **Retry Flow** (skip to Step 3B). If `terminal` is `true`, skip the item.

---

## Step 2: Read Project Config (Starting URL)

```bash
python3 shared/grok_tracker.py --project <N> get_config
```

Returns:
```json
{
  "starting_url": "https://grok.com/imagine/post/<post-id>",
  "thumbnail_id": "<post-id>"
}
```

Use `starting_url` as the navigation target in Step 3A.

---

## Step 3A: Full Flow (pending items)

1. Navigate to `starting_url` in the active Grok browser tab.
2. Load and inject `shared/grok_automation.js` via `evaluate_script`.
3. Call `automateGrokGeneration()` with:
   ```javascript
   {
     promptText: "<prompt from Step 1>",
     thumbnailId: "<thumbnail_id from Step 2>",
     videoPromptText: <video_prompt or null>,
     videoType: <video_type or null>,
     skipImageGeneration: false,
     tonedDownRetry: false
   }
   ```

---

## Step 3B: Retry Flow (video_warning / image_warning items)

1. Ensure the browser is on the item's saved `post_url` from Step 1.
2. Load and inject `shared/grok_automation.js` via `evaluate_script`.
3. Call `automateGrokGeneration()` with:
   ```javascript
   {
     promptText: "<prompt>",
     thumbnailId: "<thumbnail_id>",
     videoPromptText: null,
     videoType: null,
     skipImageGeneration: true,
     tonedDownRetry: true,
     postUrl: "<post_url from Step 1>"
   }
   ```

> **Key difference**: `skipImageGeneration: true` skips the thumbnail click, prompt input, and image submit. The script navigates directly to the saved `post_url` and clicks "Make video" immediately.

> **Retry rule**: 
> - First warning (`video_warning` or `image_warning`) → retry once.
> - If the retry also fails with the same type of issue, mark as `video_failed` or `image_failed` (terminal).

---

## Step 4: Handle the Result

The script returns `{ status, videoUrl, postUrl, error, mode }`.

| `status` | Meaning | Tracker Command |
|----------|---------|-----------------|
| `completed` | Video generated successfully | `complete <id> <video_url> <post_url>` |
| `video_warning` | Video moderated/failed/timed out on **first** attempt | `mark_video_warning <id> <post_url>` |
| `image_warning` | Image moderated on **first** attempt | `mark_image_warning <id> <post_url>` |
| `video_failed` | Second video failure or fatal error (terminal) | `mark_video_failed <id> <post_url>` |
| `image_failed` | Second image failure or fatal error (terminal) | `mark_image_failed <id> <post_url>` |
| `failed` | Fatal script error (terminal) | `mark_failed <id>` |

### Update Tracker

```bash
# Success
python3 shared/grok_tracker.py --project <N> complete <ID> "<VIDEO_URL>" "<POST_URL>"

# First video failure/moderation (will retry next run)
python3 shared/grok_tracker.py --project <N> mark_video_warning <ID> "<POST_URL>"

# First image moderation (will retry next run)
python3 shared/grok_tracker.py --project <N> mark_image_warning <ID> "<POST_URL>"

# Second video failure (terminal — no more retries)
python3 shared/grok_tracker.py --project <N> mark_video_failed <ID> "<POST_URL>"

# Second image failure (terminal — no more retries)
python3 shared/grok_tracker.py --project <N> mark_image_failed <ID> "<POST_URL>"

# Fatal script error (terminal — no more retries)
python3 shared/grok_tracker.py --project <N> mark_failed <ID>
```

---

## Automation Script Reference

The JavaScript automation logic lives in:

```
shared/grok_automation.js
```

Load it and call `automateGrokGeneration(options)` as shown above.

### Key Behaviors

- **Image Generation Polling**: Waits up to 2 minutes for the "Make video" button to appear.
- **Video Completion Polling**: After triggering video, polls for up to **6 minutes** checking for:
  - **Success**: `<video>` element with `.mp4` src, or "Pause"/"Download" buttons
  - **Video Moderation**: `svg.lucide-eye-off` present → `video_warning`
  - **Image Moderation**: `img[alt="Moderated"]` with `blur-lg saturate-0` classes → `image_warning`
  - **Failure**: Body text matching moderation/error keywords (`moderated`, `unable`, `failed`, `restricted`, etc.) → `video_warning`
  - **Timeout**: If neither success nor failure after 6 minutes → `video_warning`
- **URL Change Detection**: Waits up to 30 seconds for the page URL to update after clicking "Make video".

---

## Data Schema Reference

### Prompt Entry (Default Mode)
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

### Prompt Entry (Custom Video Prompt)
```json
{
  "id": 43,
  "prompt": "Imagine the exact model ...",
  "video_prompt": "Camera slowly pans upward...",
  "status": "pending",
  "instagram_caption": "...",
  "video_url": null,
  "post_url": null,
  "executed_at": null
}
```

### Prompt Entry (video_warning — after first video failure)
```json
{
  "id": 44,
  "prompt": "Imagine the exact model ...",
  "status": "video_warning",
  "post_url": "https://grok.com/imagine/post/...",
  "video_warning_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```

### Prompt Entry (image_warning — after first image moderation)
```json
{
  "id": 44.5,
  "prompt": "Imagine the exact model ...",
  "status": "image_warning",
  "post_url": "https://grok.com/imagine/post/...",
  "image_warning_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```

### Prompt Entry (video_failed — terminal, no more retries)
```json
{
  "id": 45,
  "prompt": "Imagine the exact model ...",
  "status": "video_failed",
  "post_url": "https://grok.com/imagine/post/...",
  "video_failed_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```

### Prompt Entry (image_failed — terminal, no more retries)
```json
{
  "id": 45.5,
  "prompt": "Imagine the exact model ...",
  "status": "image_failed",
  "post_url": "https://grok.com/imagine/post/...",
  "image_failed_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```

### Prompt Entry (failed — terminal script error)
```json
{
  "id": 46,
  "prompt": "Imagine the exact model ...",
  "status": "failed",
  "failed_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```

### Prompt Entry (completed)
```json
{
  "id": 46,
  "prompt": "Imagine the exact model ...",
  "status": "completed",
  "video_url": "https://grok.com/imagine/post/...",
  "post_url": "https://grok.com/imagine/post/...",
  "executed_at": "2026-04-28T21:00:00Z",
  "instagram_caption": "..."
}
```
