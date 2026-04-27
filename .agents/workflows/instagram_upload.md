---
description: End-to-end automation skill for uploading videos to Instagram. Works for both project-1 and project-2 based on the mapped status in grok_prompts.json. Requires --project <1|2> argument.
---

## Overview

This workflow automates the process of posting an MP4 asset to Instagram using BrowserOS. It identifies the correct asset and caption from the project's `grok_prompts.json` file, navigates to Instagram, and uploads the video.

---

### Step 1: Identify the Project and Asset

Determine which project to run for. The user will specify `--project 1` or `--project 2`. 

Run a command to extract the first pending prompt entry that has `"instagram_upload": "mapped"` in `project-<N>/grok_prompts.json`:

```bash
python3 -c "
import json
import sys
import os

project = sys.argv[1]
filepath = f'project-{project}/grok_prompts.json'
if not os.path.exists(filepath):
    print(f'File not found: {filepath}')
    sys.exit(1)

with open(filepath) as f:
    data = json.load(f)

# The JSON structure contains a 'prompts' key which holds the list of entries
for entry in data.get('prompts', []):
    if entry.get('instagram_upload') == 'mapped':
        print(f'ID: {entry[\"id\"]}')
        print(f'Caption: {entry[\"instagram_caption\"]}')
        break
" <N>
```

The output will give you the `ID` and `Caption`.
Construct the full absolute path for the asset file. For example, if your workspace is `/Users/dsen/Projects/ai-post-maker`:
`/Users/dsen/Projects/ai-post-maker/project-<N>/assets/<ID>.mp4`

Ensure you have the exact absolute path before proceeding.

---

### Step 2: Navigate to Instagram

- Use the `new_page` tool (NOT `navigate_page`) to open a **fresh tab** at `https://www.instagram.com/`.
- This is mandatory — file upload only works reliably on a fresh page where React event handlers are newly initialized.
- Note the new **Page ID** returned — use it for all subsequent tool calls in this workflow.

---

### Step 3: Execute Automation Script (Part 1 - Open Modal)

Inject and evaluate the following JavaScript snippet into the active Instagram tab using the `evaluate_script` tool from the browseros MCP.

```javascript
// IMPORTANT: Always wrap in an IIFE — evaluate_script does NOT allow top-level return statements.
(async () => {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // Helper: XPath single-node lookup
  const xpathOne = (expr) =>
    document.evaluate(expr, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;

  // 1. Click 'New post' (Create) sidebar item via XPath (most reliable)
  let createBtn = xpathOne("//svg[@aria-label='New post']/ancestor::a") ||
                  xpathOne("//a[.//span[contains(text(),'Create')]]") ||
                  document.querySelector('svg[aria-label="New post"]')?.closest('a');

  if (createBtn) {
    createBtn.click();
    await wait(2000);
  } else {
    return { success: false, error: 'Create button not found' };
  }

  // 2. Click 'Post' option from the dropdown via XPath
  //    The dropdown renders text-based menu items, not SVG-labelled links
  let postBtn = xpathOne("//span[contains(text(),'Post')]/ancestor::a") ||
                xpathOne("//span[contains(text(),'Post')]/ancestor::div[@role='button']") ||
                Array.from(document.querySelectorAll('[role="menuitem"], a'))
                  .find(el => el.textContent.trim() === 'Post');

  if (postBtn) {
    postBtn.click();
    await wait(2000);
  } else {
    return { success: false, error: 'Post menu item not found' };
  }

  return { success: true };
})();
```

---

### Step 4: Upload the Asset

> **⚠️ Critical**: This step MUST be run on a **fresh/new browser page**. Re-using an existing tab that has had prior upload attempts will cause the modal to not advance after upload. Always use `new_page` in Step 2 to open a new tab.

1. **Expose both file inputs via JavaScript**

   Instagram renders two hidden `input[type="file"]` elements inside the modal. Run this `evaluate_script` to expose them both:

   ```javascript
   // Expose all hidden file inputs so the second one ('Choose Files') appears in the next snapshot
   (() => {
     const fileInputs = document.querySelectorAll('input[type="file"]');
     Array.from(fileInputs).forEach((fi, i) => {
       fi.style.cssText = `display:block!important;visibility:visible!important;opacity:1!important;position:fixed!important;top:${10 + i * 50}px!important;left:10px!important;z-index:99999!important;width:150px!important;height:40px!important;`;
       fi.id = `ig_file_input_${i}`;
     });
     return { exposed: fileInputs.length };
   })();
   ```

2. **Take a fresh snapshot** — a new element labeled **"Choose Files"** will appear. Note its element ID (e.g. `[1806]`).

3. **Upload the file** to the **"Choose Files"** element (NOT "Select from computer"):
   - Use the `upload_file` tool with that element ID and the absolute `.mp4` path from Step 1.
   - The modal will automatically advance to the Crop screen after ~1–2 seconds once the file is set. You do NOT need to trigger any extra events.

   > **Note**: After `upload_file` returns, the modal may still appear unchanged in the snapshot. This is normal — the upload triggers asynchronously inside React. The Step 5 script's initial `await wait(2000)` handles this delay.

---

### Step 5: Execute Automation Script (Part 2 - Crop, Next, Caption, Share)

> **⚠️ CDP Timeout Risk**: Do NOT combine crop/next and caption into a single script. Total await time exceeds 15 seconds which drops the CDP connection. Run as **two separate `evaluate_script` calls** below.

#### Step 5a — Crop + Navigate to Caption Screen

```javascript
// IMPORTANT: Always wrap in an IIFE — evaluate_script does NOT allow top-level return statements.
(async () => {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  const xpathOne = (expr) =>
    document.evaluate(expr, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;

  // Wait for React to process the file upload before doing anything
  await wait(4000);

  const modalLabel = document.querySelector('div[role="dialog"]')?.getAttribute('aria-label');

  // 1. Select crop option — navigate SVG to its parent button directly
  const cropSvg = document.querySelector('svg[aria-label="Select crop"]') ||
                  document.querySelector('svg[aria-label="Crop"]');
  const cropBtn = cropSvg ? (cropSvg.closest('button') || cropSvg.parentElement) : null;
  if (cropBtn) { cropBtn.click(); await wait(1000); }

  // 2. Select "Original" aspect ratio via XPath
  const originalBtn = xpathOne("//div[@role='button'][.//span[contains(text(),'Original')]]") ||
                      xpathOne("//div[@role='button'][contains(text(),'Original')]") ||
                      Array.from(document.querySelectorAll('div[role="button"]'))
                        .find(el => el.textContent.trim().includes('Original'));
  if (originalBtn) { originalBtn.click(); await wait(1000); }

  // 3. Click Next (crop → filter/edit screen)
  let nextBtn = xpathOne("//div[@role='button'][normalize-space(text())='Next']") ||
                Array.from(document.querySelectorAll('div[role="button"]'))
                  .find(el => el.textContent.trim() === 'Next');
  if (nextBtn) { nextBtn.click(); await wait(3000); }
  else return { success: false, step: 'Next-1', modalLabel, cropFound: !!cropBtn, originalFound: !!originalBtn };

  // 4. Click Next again (filter/edit → caption screen)
  nextBtn = xpathOne("//div[@role='button'][normalize-space(text())='Next']") ||
            Array.from(document.querySelectorAll('div[role="button"]'))
              .find(el => el.textContent.trim() === 'Next');
  if (nextBtn) { nextBtn.click(); await wait(3000); }
  else return { success: false, step: 'Next-2' };

  return {
    success: true,
    modalLabelAfter: document.querySelector('div[role="dialog"]')?.getAttribute('aria-label'),
    cropFound: !!cropBtn,
    originalFound: !!originalBtn
  };
})();
```

> Verify the result shows `"success": true` and `modalLabelAfter` is `"Create new post"` before proceeding.

#### Step 5b — Enter Caption (substitute `CAPTION_PLACEHOLDER` before running)

```javascript
// IMPORTANT: Always wrap in an IIFE — evaluate_script does NOT allow top-level return statements.
(async () => {
  const captionText = `CAPTION_PLACEHOLDER`;
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  const xpathOne = (expr) =>
    document.evaluate(expr, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;

  // Find caption textbox — XPath primary, aria-label fallback, contenteditable last resort
  const editableBox = xpathOne("//div[@role='textbox'][contains(@aria-label,'caption')]") ||
                      document.querySelector('div[role="textbox"][aria-label="Write a caption..."]') ||
                      document.querySelector('div[contenteditable="true"]');

  if (!editableBox) return {
    success: false,
    step: 'caption',
    error: 'Caption box not found',
    allTextboxLabels: Array.from(document.querySelectorAll('[role="textbox"]')).map(el => el.getAttribute('aria-label'))
  };

  editableBox.focus();
  editableBox.click();
  document.execCommand('insertText', false, captionText);
  editableBox.dispatchEvent(new Event('input', { bubbles: true }));
  await wait(1000);

  // Locate Share button — verify it's present but DO NOT click it
  const shareBtn = xpathOne("//div[@role='button'][normalize-space(text())='Share']") ||
                   Array.from(document.querySelectorAll('div[role="button"]'))
                     .find(el => el.textContent.trim() === 'Share');

  return {
    success: true,
    captionEntered: editableBox.textContent.substring(0, 120),
    shareBtnFound: !!shareBtn,
    modalLabel: document.querySelector('div[role="dialog"]')?.getAttribute('aria-label')
  };
})();
```

> **After Step 5b returns**: Confirm `captionEntered` looks correct and `shareBtnFound` is `true`. Then use `take_snapshot` → `click` the Share button element to publish.

#### Step 5c — Abort / Discard (dry-run cleanup only, do NOT run when publishing)

```javascript
// Dismiss the modal and discard the draft without posting
(() => {
  const closeSvg = document.querySelector('svg[aria-label="Close"]');
  if (closeSvg) { (closeSvg.closest('button') || closeSvg.parentElement).click(); return { closed: true }; }
  return { closed: false };
})();
```

Then after ~1 second, click **Discard** in the confirmation dialog:

```javascript
(() => {
  const discardBtn = Array.from(document.querySelectorAll('button'))
    .find(b => b.textContent.trim() === 'Discard');
  if (discardBtn) { discardBtn.click(); return { discarded: true }; }
  return { discarded: false, note: 'Dialog may have auto-dismissed already' };
})();
```

---

### Step 6: Verify and Update Status

1. **Verify Success**: 
   - Check for a "Your post has been shared" message or similar.
   - Use `take_snapshot` to confirm the modal has closed or success UI is visible.

2. **Update JSON**:
   - Once confirmed, update the prompt entry in `project-<N>/grok_prompts.json` to `"instagram_upload": "done"`.
   - Use `replace_file_content` to make this change.

