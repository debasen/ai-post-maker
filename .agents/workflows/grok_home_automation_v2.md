---
description: Grok Home Automation v2 — Deterministic step-by-step workflow for generating assets on Grok. Uses search_dom for element existence verification and explicit decision trees.
---

# Grok Image & Video Generation Rule Book v2

This document is a deterministic, step-by-step procedure. Follow each step exactly as written. Do not skip steps or make independent decisions.

## Constants

- `PROJECT_ID`: The project number passed via `--project` argument (e.g., `1`)
- `TRACKER_SCRIPT`: `scripts/py/grok_tracker.py`
- `DOWNLOADER_SCRIPT`: `scripts/py/grok_video_downloader.py`
- `ASSETS_DIR`: `project-<PROJECT_ID>/assets/current/`
- `GROK_IMAGINE_URL`: `https://grok.com/imagine`

---

## Phase 1: Preparation

### Step 1.1: Get Next Pending Record

Run the tracker to retrieve the next pending prompt:

```bash
python3 <TRACKER_SCRIPT> --project <PROJECT_ID> get_next
```

**Expected output**: A JSON object.

**Decision tree**:
- If output contains `"error": "No pending or warning prompts"` → **TERMINATE WORKFLOW**
- Otherwise, extract these exact fields into variables:
  - `RECORD_ID` = value of `id`
  - `PROMPT_TEXT` = value of `prompt`
  - `VIDEO_PROMPT` = value of `video_prompt` (may be null/absent)
  - `EXTEND_PROMPT` = value of `extend_prompt` (may be null/absent)
  - `STATUS` = value of `status` (starting status)

**DO NOT PROCEED** if no pending record exists.

---

## Phase 2: Platform Navigation

### Step 2.1: Navigate to Grok Imagine

Call `browseros_navigate_page` with:
- `url`: `https://grok.com/imagine`

Wait 5 seconds after navigation completes.

### Step 2.2: Verify Page Load

Call `browseros_search_dom` with:
- `query`: `[contenteditable="true"]`
- `limit`: 5

**Decision tree**:
- If results found → Proceed to Phase 3
- If no results → Wait 5 seconds and repeat Step 2.2 (max 3 attempts)
- If still no results after 3 attempts → **TERMINATE WORKFLOW** and report page load failure

---

## Phase 3: Image Generation

### Step 3.1: Verify Input Field Exists

Call `browseros_search_dom` with:
- `query`: `div[contenteditable="true"]`
- `limit`: 5

**Decision tree**:
- If at least 1 result → Proceed to Step 3.2
- If no results → **TERMINATE WORKFLOW** and report input not found

### Step 3.2: Enter Prompt Text (Evaluate Script Required)

**NOTE**: `browseros_type_at` does NOT work reliably with ProseMirror contenteditable editors. Use `evaluate_script` with the following exact expression:

```javascript
(function() {
  const el = document.querySelector('div[contenteditable="true"]');
  if (!el) return JSON.stringify({error: 'Input not found'});
  
  el.click();
  el.focus();
  
  // Small delay for focus
  setTimeout(() => {
    el.textContent = 'REPLACE_WITH_PROMPT_TEXT';
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }, 1000);
  
  return JSON.stringify({success: true});
})()
```

Replace `REPLACE_WITH_PROMPT_TEXT` with the exact `PROMPT_TEXT` value.

Wait 3 seconds after execution.

### Step 3.3: Verify Text Entry

Call `browseros_search_dom` with:
- `query`: `button[aria-label="Submit"]`
- `limit`: 5

**Decision tree**:
- If found and button is NOT disabled → Proceed to Step 3.4
- If found but disabled → Wait 3 seconds and repeat (max 3 attempts)
- If not found → Call `browseros_search_dom` with `query: button[aria-label="Grok"]` or `button[aria-label="Send"]`
  - If found and not disabled → Proceed to Step 3.4
  - If still not found or disabled → **TERMINATE WORKFLOW** with text entry failure

### Step 3.4: Submit Prompt

Call `browseros_take_snapshot`.
Find the Submit button (element with `aria-label="Submit"`, `"Grok"`, or `"Send"`).
Call `browseros_click` with the element ID.

Wait 5 seconds.

### Step 3.5: Wait for Image Generation

Wait 15 seconds for initial generation.

Call `browseros_search_dom` with:
- `query`: `img[alt="Generated image"]`
- `limit`: 10

**Decision tree**:
- If at least 1 result found → Proceed to Phase 4
- If no results → Wait 10 seconds and repeat Step 3.5 (max 12 attempts = 120 seconds total)
- If after 12 attempts still no results → Proceed to Step 3.6

### Step 3.6: Check for Moderation/Error

Call `browseros_search_dom` with:
- `query`: `svg.lucide-eye-off`
- `limit`: 5

**Decision tree**:
- If eye-off SVG found → **IMAGE MODERATED** → Proceed to Step 3.7 (Retry with toned-down prompt)
- If not found → Call `browseros_get_page_content` and check for text patterns: `moderated`, `unable to generate`, `failed`, `restricted`, `policy`, `cannot create`, `blocked`
- If any pattern found → **IMAGE MODERATED** → Proceed to Step 3.7
- If no patterns → **Mark as image_failed** (Phase 8A) → **TERMINATE RECORD**

### Step 3.7: Tone Down Prompt and Retry (Image Retry)

**ONLY execute if STATUS was `pending`. If STATUS was `image_warning` → Go directly to Phase 8A.**

Tone-down rules (apply ALL of the following):
1. Remove words: `sexy`, `naked`, `nude`, `erotic`, `suggestive`, `provocative`, `seductive`, `intimate`
2. Replace `skimpy clothing` with `casual clothing`
3. Replace `tight/revealing` with `loose/modest`
4. Remove explicit body descriptions (e.g., `large breasts`, `muscular abs`)
5. Keep core scene description intact

Repeat Steps 3.1 through 3.6 with toned-down prompt.

**Decision tree after retry**:
- If images appear → Proceed to Phase 4
- If moderated again → **Mark as image_failed** (Phase 8A) → **TERMINATE RECORD**

---

## Phase 4: Video Generation

### Step 4.1: Open Image Detail View

Call `browseros_search_dom` with:
- `query`: `img[alt="Generated image"]`
- `limit`: 5

**Decision tree**:
- If at least 1 result → Use `evaluate_script` to get coordinates of FIRST image:
  ```javascript
  (function() {
    const el = document.querySelector('img[alt="Generated image"]');
    if (el) {
      const rect = el.getBoundingClientRect();
      return JSON.stringify({x: rect.left + rect.width/2, y: rect.top + rect.height/2, found: true});
    }
    return JSON.stringify({found: false});
  })()
  ```
  Then call `browseros_click_at` with the returned x, y.
- If no results → Call `browseros_take_snapshot`, find first `link` element, and call `browseros_click` with the element ID.

Wait 3 seconds.

### Step 4.2: Verify Detail View

Call `browseros_search_dom` with:
- `query`: `button[aria-label="Make video"]`
- `limit`: 5

**Decision tree**:
- If found → Proceed to Step 4.3
- If not found → Wait 3 seconds and repeat (max 5 attempts)
- If still not found → **Mark as image_failed** (Phase 8A) → **TERMINATE RECORD**

### Step 4.3: Click Make Video Button

Call `browseros_take_snapshot`.
Find the interactive element with `aria-label="Make video"`.
Call `browseros_click` with the element ID.

Wait 2 seconds.

### Step 4.4: Handle Custom Video Prompt (if applicable)

**Decision tree**:
- If `VIDEO_PROMPT` is non-null and non-empty → Proceed to Step 4.5
- If `VIDEO_PROMPT` is null or empty → Skip to Step 4.6 (default mode)

### Step 4.5: Enter Custom Video Prompt

Call `browseros_search_dom` with:
- `query`: `textarea, [contenteditable="true"]`
- `limit`: 5

If found, use `evaluate_script` to set text:
```javascript
(function() {
  const el = document.querySelector('textarea') || document.querySelector('[contenteditable="true"]');
  if (!el) return 'NOT_FOUND';
  el.focus();
  el.value = 'REPLACE_WITH_VIDEO_PROMPT';
  el.dispatchEvent(new Event('input', { bubbles: true }));
  return 'SET_OK';
})()
```

Call `browseros_press_key` with:
- `key`: `Enter`

### Step 4.6: Verify Video Generation Started

Wait 5 seconds.

Call `browseros_search_dom` with:
- `query`: `//button[normalize-space()='Cancel Video']`
- `limit`: 5

**Decision tree**:
- If Cancel Video button found → Video generation is in progress → Proceed to Phase 5
- If not found → Call `browseros_search_dom` with `query: svg.lucide-eye-off`
  - If eye-off found → **VIDEO MODERATED** → Proceed to Step 4.7 (Video Retry)
  - If not found → Call `browseros_get_page_content` and check for: `moderated`, `unable to generate`, `failed`, `restricted`
    - If found → **VIDEO MODERATED** → Proceed to Step 4.7
    - If not found → Wait 5 seconds and repeat Step 4.6 (max 3 attempts)
    - If still not found after 3 attempts → **Mark as video_failed** (Phase 8B) → **TERMINATE RECORD**

### Step 4.7: Tone Down Video Prompt and Retry (Video Retry)

**ONLY execute if VIDEO_PROMPT is non-null and non-empty AND STATUS was `pending` or `image_warning`.**
**If STATUS was `video_warning` → Go directly to Phase 8B.**
**If VIDEO_PROMPT is null/empty → Go directly to Phase 8B.**

Tone-down rules for video prompt:
1. Remove explicit camera directions (`zoom in on`, `close up of`, `focus on`)
2. Remove motion intensity words (`violent`, `aggressive`, `rapid`, `intense`)
3. Replace with calmer alternatives (`gentle`, `smooth`, `slow`)
4. Keep core action description

Navigate back to image detail view by calling `browseros_navigate_page` with the current post URL (extract from `browseros_evaluate_script` with `window.location.href`).

Repeat Steps 4.2 through 4.6 with toned-down `VIDEO_PROMPT`.

**Decision tree after retry**:
- If video generation starts → Proceed to Phase 5
- If moderated/failed again → **Mark as video_failed** (Phase 8B) → **TERMINATE RECORD**

---

## Phase 5: Monitoring & Validation

### Step 5.1: Poll for Video Completion

Set `attempts = 0`, `max_attempts = 40` (approx 2 minutes with 3-second intervals).

**Loop** (while `attempts < max_attempts`):

1. Wait 3 seconds
2. Increment `attempts`
3. Call `browseros_search_dom` with:
   - `query`: `button[aria-label="Download"]`
   - `limit`: 5
4. **Decision tree**:
   - If Download button found AND not disabled → Video complete → Proceed to Phase 6
   - If not found → Call `browseros_search_dom` with:
     - `query`: `button[aria-label="Pause"]`
     - `limit`: 5
     - If Pause button found → Video is playing/ready → Proceed to Phase 6
5. Call `browseros_search_dom` with:
   - `query`: `svg.lucide-eye-off`
   - `limit`: 5
   - If found → **VIDEO MODERATED** during generation → Proceed to Step 4.7 if retry available, else Phase 8B
6. Call `browseros_search_dom` with:
   - `query`: `//span[contains(text(),'Generating')]`
   - `limit`: 5
   - If found → Note percentage if visible, continue loop
7. Call `browseros_get_page_content` (viewport only)
   - Check for text: `moderated`, `unable to generate`, `failed`, `restricted`, `policy`, `cannot create`, `blocked`, `error generating`
   - If any found → **VIDEO FAILED** → Proceed to Step 4.7 if retry available, else Phase 8B

**If loop exits after max_attempts**:
- **Mark as video_failed** (Phase 8B) → **TERMINATE RECORD**

---

## Phase 6: Asset Management

### Step 6.1: Locate Download Button

Call `browseros_take_snapshot`.

Find the interactive element with `aria-label="Download"`.
Note its element ID.

**Decision tree**:
- If found → Proceed to Step 6.2
- If not found → Call `browseros_search_dom` with:
  - `query`: `button[aria-label="Download"]`
  - `limit`: 5
  - If found via search_dom → Use `evaluate_script` to get coordinates, then `browseros_click_at`
  - If not found → **TERMINATE RECORD** with download button not found error

### Step 6.2: Download Video File

Wait 5 seconds for file stabilization.

Call `browseros_download_file` with:
- `element`: Element ID from Step 6.1
- `path`: `/Users/dsen/Projects/ai-post-maker/<ASSETS_DIR>`

Wait 5 seconds for download to complete.

### Step 6.3: Rename Downloaded File

Run:

```bash
python3 <DOWNLOADER_SCRIPT> --project <PROJECT_ID> process_download <ASSETS_DIR> <RECORD_ID>
```

### Step 6.4: Verify File

Run:

```bash
ls -la /Users/dsen/Projects/ai-post-maker/<ASSETS_DIR><RECORD_ID>.mp4
```

**Decision tree**:
- If file exists with size > 0 bytes → Proceed to Phase 7
- If file does not exist or size is 0 → **REPORT ERROR** but still proceed to Phase 7 (tracker update)

---

## Phase 7: Recording & Tracking

### Step 7.1: Get Current URLs

Call `browseros_evaluate_script` with:
- `expression`: `window.location.href`

Store result as `POST_URL`.

Call `browseros_search_dom` with:
- `query`: `video`
- `limit`: 5

If video element found, call `browseros_evaluate_script` with:
- `expression`: `document.querySelector('video')?.src || 'N/A'`

Store result as `VIDEO_URL`.

### Step 7.2: Update Tracker

**Decision tree**:
- If reached from Phase 6 (successful download) → Mark as completed:
  ```bash
  python3 <TRACKER_SCRIPT> --project <PROJECT_ID> complete <RECORD_ID> "<VIDEO_URL>" "<POST_URL>"
  ```
- If workflow is terminating due to image failure and this is FIRST failure (STATUS was `pending`) → Mark as image_warning:
  ```bash
  python3 <TRACKER_SCRIPT> --project <PROJECT_ID> mark_image_warning <RECORD_ID> "<POST_URL>"
  ```
- If workflow is terminating due to image failure and this is SECOND failure (STATUS was `image_warning`) → Mark as image_failed:
  ```bash
  python3 <TRACKER_SCRIPT> --project <PROJECT_ID> mark_image_failed <RECORD_ID> "<POST_URL>"
  ```
- If workflow is terminating due to video failure and this is FIRST failure (STATUS was `pending` or `image_warning`) → Mark as video_warning:
  ```bash
  python3 <TRACKER_SCRIPT> --project <PROJECT_ID> mark_video_warning <RECORD_ID> "<POST_URL>"
  ```
- If workflow is terminating due to video failure and this is SECOND failure (STATUS was `video_warning`) → Mark as video_failed:
  ```bash
  python3 <TRACKER_SCRIPT> --project <PROJECT_ID> mark_video_failed <RECORD_ID> "<POST_URL>"
  ```

---

## Phase 8: Terminal Status Handlers

### Phase 8A: Image Failed

Execute Step 7.2 with the appropriate image failure command based on retry count.

**TERMINATE RECORD**.

### Phase 8B: Video Failed

Execute Step 7.2 with the appropriate video failure command based on retry count.

**TERMINATE RECORD**.

---

## Error Handling Matrix

| Scenario | Starting Status | Action | Result Status |
|----------|----------------|--------|---------------|
| Image moderated, 1st failure | `pending` | Tone down prompt, retry | `image_warning` |
| Image moderated, 2nd failure | `image_warning` | No retry | `image_failed` |
| Image timeout (no error) | any | No retry | `image_failed` |
| Video moderated, 1st failure | `pending`/`image_warning` | Tone down video_prompt, retry | `video_warning` |
| Video moderated, 2nd failure | `video_warning` | No retry | `video_failed` |
| Video timeout | any | No retry | `video_failed` |
| Download missing | `completed` | Report error, keep `completed` | `completed` |

---

## Tool Reference

### `browseros_search_dom` queries used in this workflow:

| Purpose | Query | Type |
|---------|-------|------|
| Find input field | `div[contenteditable="true"]` | CSS |
| Find generated images | `img[alt="Generated image"]` | CSS |
| Find moderation icon | `svg.lucide-eye-off` | CSS |
| Find Make Video button | `button[aria-label="Make video"]` | CSS |
| Find Cancel Video button | `//button[normalize-space()='Cancel Video']` | XPath |
| Find Download button | `button[aria-label="Download"]` | CSS |
| Find Pause button | `button[aria-label="Pause"]` | CSS |
| Find video element | `video` | CSS |
| Find generation indicator | `//span[contains(text(),'Generating')]` | XPath |

### `browseros_take_snapshot` usage:

Called when:
- Clicking Submit button (Step 3.4)
- Fallback for finding image links (Step 4.1)
- Clicking Make Video button (Step 4.3)
- Locating Download button by element ID (Step 6.1)

### `browseros_evaluate_script` usage:

Called when:
- Setting text in ProseMirror editor (Step 3.2)
- Getting coordinates for image click (Step 4.1)
- Setting video prompt text (Step 4.5)
- Getting current URL (Step 7.1)
- Getting video src URL (Step 7.1)

---

## Execution Notes

1. **No AI Decisions**: This workflow is deterministic. Every decision point has explicit conditions. Do not improvise.
2. **Element IDs are Dynamic**: Always use `take_snapshot` to discover interactive element IDs at runtime. Never hardcode element IDs.
3. **Coordinates Change**: Window size and zoom affect coordinates. Always use `evaluate_script` to get fresh coordinates before using `type_at` or `click_at`.
4. **Text Verification**: When checking page content for errors, use `browseros_get_page_content` with `viewportOnly: true` for speed.
5. **Retry Limits**: Image retry = 1. Video retry = 1. No additional retries.
6. **Project Parameterization**: Replace `<PROJECT_ID>` with the actual argument (e.g., `1`). Replace `<TRACKER_SCRIPT>`, `<DOWNLOADER_SCRIPT>`, `<ASSETS_DIR>` with their defined values.
7. **ProseMirror Editor**: The Grok input uses a ProseMirror editor. `type_at` does not work reliably. Always use `evaluate_script` to set `textContent` and dispatch `input`/`change` events.
8. **Submit Button Verification**: Always verify the Submit button is enabled before clicking. If it remains disabled after text entry, the text was not properly registered.

---

## Gaps Identified During v2 Testing

The following gaps were discovered while executing this workflow with `--project 1`:

### Gap 1: search_dom Cannot Drive Actions Directly
- **Issue**: `browseros_search_dom` returns nodeIds and tag info, but NOT coordinates (for `type_at`/`click_at`) or snapshot element IDs (for `click`/`fill`).
- **Impact**: Every "find element → interact" step requires a SECOND tool call (`evaluate_script` for coordinates, or `take_snapshot` for element IDs).
- **Mitigation**: Documented in v2 workflow — always pair `search_dom` with `evaluate_script` (coordinates) or `take_snapshot` (element IDs).

### Gap 2: type_at Fails on ProseMirror Editors
- **Issue**: `browseros_type_at` sends keystrokes to coordinates but Grok's ProseMirror editor requires focus + `textContent` mutation + `input`/`change` event dispatch.
- **Impact**: Prompt text is not entered; Submit button remains disabled; generation never starts.
- **Mitigation**: Step 3.2 now uses `evaluate_script` exclusively for text entry.

### Gap 3: No Text Entry Verification
- **Issue**: Original v1 did not verify text was actually entered before pressing Enter.
- **Impact**: Silent failures where empty prompts are submitted.
- **Mitigation**: Added Step 3.3 to verify Submit button is enabled before proceeding.

### Gap 4: Snapshot Element IDs Are Ephemeral
- **Issue**: Element IDs from `take_snapshot` (e.g., `[3779]`) change between page reloads and sometimes between interactions.
- **Impact**: Hardcoding element IDs from examples will fail.
- **Mitigation**: Workflow explicitly states to call `take_snapshot` at runtime for every interaction.

### Gap 5: search_dom and take_snapshot Use Different ID Spaces
- **Issue**: `search_dom` returns `nodeId` values; `take_snapshot` returns bracketed `[elementId]` values. These are NOT interchangeable.
- **Impact**: Cannot use `search_dom` result to directly call `browseros_click`.
- **Mitigation**: Workflow documents using `search_dom` for existence checking and `take_snapshot` for getting clickable element IDs.

### Gap 6: No Pre-flight Browser Health Check
- **Issue**: Workflow assumes browser is responsive. No check for crashed tabs, offline state, or CAPTCHA walls.
- **Impact**: Steps may fail silently on unresponsive browsers.
- **Mitigation**: Could add a pre-flight `evaluate_script` with `navigator.userAgent` check.

### Gap 7: Extend Video Flow Not Tested
- **Issue**: Project 1 prompts do not have `extend_prompt` fields, so Phase 4.5-4.7 (extend flow) was not exercised.
- **Impact**: Unknown whether extend prompt input uses same ProseMirror editor or a textarea.
- **Mitigation**: Extend flow uses same `evaluate_script` pattern as Step 3.2 as a safe default.

### Gap 8: Image Click Coordinate Discovery is Brittle
- **Issue**: Using `evaluate_script` to get `img[alt="Generated image"]` coordinates assumes the first image is always clickable.
- **Impact**: If Grok changes the image layout or alt text, the click will miss.
- **Mitigation**: Added fallback to `take_snapshot` + click first `link` element.

### Gap 9: No Handling for "Generate More" Flow
- **Issue**: If all 4 initial images are moderated, Grok offers a "Generate More" button. The v2 workflow does not handle this.
- **Impact**: Record may be incorrectly marked as `image_failed` when a retry with "Generate More" could succeed.
- **Mitigation**: The existing `grok_automation_v2.js` handles this. The workflow document should reference it or add explicit steps.

### Gap 10: Post-Submit Navigation Detection is Weak
- **Issue**: After clicking Submit, the workflow waits 15 seconds then checks for images. There's no detection of "generation in progress" state.
- **Impact**: If generation takes longer than 15 seconds, the workflow may proceed to moderation check prematurely.
- **Mitigation**: Could poll for generation indicators (spinners, "Generating" text) before checking for completion.
