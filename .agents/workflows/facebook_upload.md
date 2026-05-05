---
description: End-to-end automation skill for uploading videos to Facebook. Works for both project-1 and project-2 based on the asset mapping in grok_prompts.json. Requires --project <1|2> argument. Deterministic execution
---

## Overview

This workflow automates the process of posting exactly one MP4 asset to Facebook Reels using BrowserOS. It identifies the first available mapped asset, completes the upload process, and stops before the final Post click for manual review.

Execution rules:
- Follow steps in exact order. Do not skip, reorder, or add steps.
- If any verification step fails, STOP immediately and report failure. Do not retry or improvise.
- Do not make decisions. Only execute the exact command or action specified.

---

### Step 1: Identify the Project and Asset

**Action 1.1**: Run this exact command (replace `<1|2>` with the project number provided by user):

```bash
python3 scripts/py/get_mapped_post.py --project <1|2> --platform facebook
```

**Verification 1.1**: The output must contain two lines: `ID: <value>` and `Caption: <value>`. If either is missing, STOP and report failure.

**Action 1.2**: Extract the `ID` value and `Caption` value from the output. Store them as variables `ASSET_ID` and `CAPTION`.

**Action 1.3**: Construct the absolute file path: `/Users/dsen/Projects/ai-post-maker/project-<N>/assets/<ASSET_ID>.mp4`

**Action 1.4**: Verify the file exists by running:

```bash
ls -lh /Users/dsen/Projects/ai-post-maker/project-<N>/assets/<ASSET_ID>.mp4
```

**Verification 1.4**: The command must return file details without error. If file not found, STOP and report failure.

---

### Step 2: Read Facebook Reels URL

**Action 2.1**: Run this exact command (replace `<N>` with project number):

```bash
python3 -c "import json; data=json.load(open('project-<N>/grok_prompts.json')); print(data['config']['facebook_reels_url'])"
```

**Verification 2.1**: The output must be a valid URL starting with `https://`. If not, STOP and report failure.

**Action 2.2**: Store the URL output as variable `FB_URL`.

---

### Step 3: Open Facebook Reels Page

**Action 3.1**: Execute `browseros_new_page` with URL = `FB_URL`.

**Action 3.2**: Store the returned Page ID as variable `PAGE_ID`.

**Action 3.3**: Wait exactly 5 seconds.

**Action 3.4**: Execute `browseros_take_snapshot` on `PAGE_ID`.

**Verification 3.4**: The snapshot must contain either element `button "Create reel"` or element `link "Reels"`. If neither exists, STOP and report failure.

---

### Step 4: Open the "Create Reel" Dialog

**Action 4.1**: Execute `browseros_click` on the element `button "Create reel"` from the snapshot.

**Action 4.2**: Wait exactly 3 seconds.

**Action 4.3**: Execute `browseros_take_snapshot` on `PAGE_ID`.

**Action 4.4**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
document.querySelector('div[role="dialog"] h2')?.innerText === 'Create reel' ||
document.querySelector('div[aria-label="Create reel"]') !== null ||
document.querySelector('div[role="dialog"]')?.innerText?.includes('Add Video')
```

**Verification 4.4**: The result must be `true`. If `false`, STOP and report failure.

---

### Step 5: Upload the Video File

**Action 5.1**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
document.querySelectorAll('input[type="file"]').forEach(i => {
  i.style.display = 'block';
  i.style.visibility = 'visible';
  i.style.opacity = '1';
});
```

**Action 5.2**: Execute `browseros_take_snapshot` on `PAGE_ID`.

**Action 5.3**: Find the first `button "Choose File"` element ID in the snapshot. Store as variable `CHOOSE_FILE_BTN_ID`.

**Action 5.4**: Execute `browseros_upload_file` with:
- `page`: `PAGE_ID`
- `element`: `CHOOSE_FILE_BTN_ID`
- `files`: `["/Users/dsen/Projects/ai-post-maker/project-<N>/assets/<ASSET_ID>.mp4"]`

**Action 5.5**: Wait exactly 15 seconds.

**Action 5.6**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const dialog = document.querySelector('div[role="dialog"]');
const text = dialog ? dialog.innerText : document.body.innerText;
const hasSafe = dialog ? dialog.innerText.includes('Your reel is safe to publish!') : false;
const hasNext = Array.from(dialog?.querySelectorAll('div[role="button"]') || []).some(b => b.innerText?.includes('Next'));
hasSafe && hasNext
```

**Verification 5.6**: If result is not `true`, repeat Action 5.5 and Action 5.6 up to 15 more times (total 16 attempts, ~4 minutes). If still not `true` after 16 attempts, STOP and report failure.

**Action 5.7**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const dialog = document.querySelector('div[role="dialog"]');
const hasSafe = dialog ? dialog.innerText.includes('Your reel is safe to publish!') : false;
const hasNext = !!dialog?.querySelector('div[role="button"]')?.innerText?.includes('Next');
hasSafe && hasNext
```

**Verification 5.7**: Result must be `true`. If `false`, STOP and report failure.

---

### Step 6: Navigate to Caption Screen

**Action 6.1**: Execute `browseros_click` on the element `button "Next"` from the snapshot.

**Action 6.2**: Wait exactly 3 seconds.

**Action 6.3**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
!!document.querySelector('[contenteditable="true"]') ||
!!document.querySelector('div[role="textbox"]') ||
!!document.querySelector('[aria-placeholder*="Describe your reel"]')
```

**Verification 6.3**: Result must be `true`. If `false`, STOP and report failure.

---

### Step 7: Enter the Caption

**Action 7.1**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const el = document.querySelector('[contenteditable="true"]') ||
           document.querySelector('div[role="textbox"]') ||
           document.querySelector('[aria-placeholder*="Describe your reel"]');
if (el) { el.click(); el.focus(); }
!!el
```

**Verification 7.1**: Result must be `true`. If `false`, STOP and report failure.

**Action 7.2**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
document.activeElement.innerText = '';
```

**Action 7.3**: Execute `browseros_evaluate_script` on `PAGE_ID` with this exact JavaScript (replace `<CAPTION>` with the actual caption text from Step 1):

```javascript
(() => {
  const el = document.activeElement;
  el.focus();
  document.execCommand('insertText', false, `<CAPTION>`);
})()
```

**Action 7.4**: Wait exactly 2 seconds.

**Action 7.5**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const text = document.activeElement?.innerText || '';
text.length > 50
```

**Verification 7.5**: Result must be `true` (caption is present and non-trivial). If `false`, STOP and report failure.

---

### Step 8: Navigate to Final Review Screen

**Action 8.1**: Execute `browseros_click` on the element `button "Next"` from the snapshot.

**Action 8.2**: Wait exactly 3 seconds.

**Action 8.3**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const dialog = document.querySelector('div[role="dialog"]');
const text = dialog ? dialog.innerText : document.body.innerText;
const hasHeading = text.includes('Reel settings');
const hasPost = !!dialog?.querySelector('div[role="button"]')?.innerText?.includes('Post');
const hasSafe = text.includes('Your reel is safe to publish!');
hasHeading && hasPost && hasSafe
```

**Verification 8.3**: Result must be `true`. If `false`, STOP and report failure.

---

### Step 9: STOP — Manual Review

**Action 9.1**: Execute `browseros_evaluate_script` on `PAGE_ID` with:

```javascript
const postBtn = Array.from(document.querySelectorAll('div[role="button"]')).find(
  b => b.innerText?.includes('Post')
);
postBtn && !postBtn.disabled && postBtn.offsetParent !== null
```

**Verification 9.1**: Result must be `true` (Post button exists and is enabled). If `false`, wait 3 seconds and retry once. If still `false`, STOP and report failure.

**Action 9.2**: Report to the user:
- Asset ID: `ASSET_ID`
- Project: `project-<N>`
- Status: Ready to publish
- Next step: User must manually click the `Post` button

**Action 9.3**: STOP. Do not click `Post`. Do not proceed further without explicit user confirmation.

---

### Step 10: Mark Record as Done (Post-User Confirmation)

**Action 10.1**: Only execute this step after the user explicitly confirms the post was published.

**Action 10.2**: Run this exact command:

```bash
python3 scripts/py/grok_tracker.py --project <N> mark_uploaded <ASSET_ID> facebook
```

**Verification 10.2**: Command must exit with code 0. If error, STOP and report failure.

**Action 10.3**: Report to the user:
- Record ID `<ASSET_ID>` is marked as uploaded for `facebook` in `project-<N>/grok_prompts.json`
- Workflow complete

---

### Step 11: Close Browser Tab

**Action 11.1**: Execute `browseros_close_page` on `PAGE_ID`.

**Action 11.2**: Report workflow completion.

(End of file)