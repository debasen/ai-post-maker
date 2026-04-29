---
description: Advanced end-to-end automation skill for generating videos on Grok. Requires --project <1|2> argument.
---

## Step 1: Get Next Record

1. **Retrieve Next Task**:
   ```bash
   python3 scripts/py/grok_tracker.py --project <N> get_next
   ```
2. **Extract Parameters**:
   - `id`, `prompt`, `status`, `video_prompt`, `video_type`, `post_url`.
   - Starting status is `status` from this output.

## Step 2: Read Config

1. **Retrieve Configuration**:
   ```bash
   python3 scripts/py/grok_tracker.py --project <N> get_config
   ```
2. **Extract Parameters**:
   - `starting_url`, `thumbnail_id`.

## Step 3A: Full Flow (pending / image_warning)

1. **Navigate**:
   - Navigate the active page to `starting_url`.
2. **Automate Generation**:
   - Prepare a script by wrapping everything in an `(async () => { ... })()` block:
     ```javascript
     (async () => {
       // Prepend content of scripts/js/grok_automation.min.js
       return await automateGrokGeneration({
         promptText: "<prompt>",
         thumbnailId: "<thumbnail_id>",
         videoPromptText: "<video_prompt>" or null,
         videoType: "<video_type>" or null,
         skipImageGeneration: false
       });
     })();
     ```
   - Call `evaluate_script` with the prepared script.
3. **Decision**:
   - If returns `status: 'ok'` → Go to Step 4.
   - If returns `status: 'image_warning'`:
     - If starting status was `pending` → Step 6A-i.
     - If starting status was `image_warning` → Step 6A-ii.
   - If returns `status: 'video_warning'` → Step 6B-i.

## Step 3B: Video-Only Flow (video_warning)

1. **Navigate**:
   - Navigate the active page to `post_url`.
2. **Automate Video Trigger**:
   - Prepare a script by wrapping everything in an `(async () => { ... })()` block:
     ```javascript
     (async () => {
       // Prepend content of scripts/js/grok_automation.min.js
       return await automateGrokGeneration({
         skipImageGeneration: true,
         postUrl: "<post_url>"
       });
     })();
     ```
   - Call `evaluate_script` with the prepared script.
3. **Decision**:
   - If returns `status: 'ok'` → Go to Step 4.
   - If returns `status: 'video_warning'` → Step 6B-ii.

## Step 4: Sleep

1. **Wait**:
   - Pause for 100 seconds to allow for processing.

## Step 5: Check Completion

1. **Verify Completion**:
   - Prepare a script by wrapping everything in an `(async () => { ... })()` block:
     ```javascript
     (async () => {
       // Prepend content of scripts/js/grok_check.min.js
       return await checkVideoCompletion();
     })();
     ```
   - Call `evaluate_script` with the prepared script.
2. **Decision**:
   - If returns `status: 'completed'` → Step 6C.
   - If returns `status: 'video_warning'`:
     - If starting status was `pending` or `image_warning` → Step 6B-i.
     - If starting status was `video_warning` → Step 6B-ii.

## Step 6: Update Tracker

### 6A-i: First Image Failure
1. Generate a toned-down `prompt`.
2. Update prompt: `python3 scripts/py/grok_tracker.py --project <N> update_field <ID> prompt "<new>"`
3. Mark status: `python3 scripts/py/grok_tracker.py --project <N> mark_image_warning <ID> "<POST_URL>"`

### 6A-ii: Second Image Failure
1. Mark failed: `python3 scripts/py/grok_tracker.py --project <N> mark_image_failed <ID> "<POST_URL>"`

### 6B-i: First Video Failure
1. Generate a toned-down `video_prompt` (if exists).
2. Update prompt: `python3 scripts/py/grok_tracker.py --project <N> update_field <ID> video_prompt "<new>"`
3. Mark status: `python3 scripts/py/grok_tracker.py --project <N> mark_video_warning <ID> "<POST_URL>"`

### 6B-ii: Second Video Failure
1. Mark failed: `python3 scripts/py/grok_tracker.py --project <N> mark_video_failed <ID> "<POST_URL>"`

### 6C: Success
1. Complete record: `python3 scripts/py/grok_tracker.py --project <N> complete <ID> "<VIDEO_URL>" "<POST_URL>"`
