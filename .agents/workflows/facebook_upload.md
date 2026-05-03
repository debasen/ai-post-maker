---
description: End-to-end automation skill for uploading videos to Facebook. Works for both project-1 and project-2 based on the asset mapping in grok_prompts.json. Requires --project <1|2> argument.
---

## Overview

This workflow automates the process of posting **exactly one** MP4 asset to Facebook Reels using BrowserOS. It identifies the first available mapped asset, completes the upload process, and stops before the final "Post" click for manual review.

---

### Step 1: Identify the Project and Asset

Determine which project to run for. The user will specify `--project 1` or `--project 2`. 

Run the following command to identify the first available asset with "mapped" status and extract its ID and Caption:

```bash
python3 scripts/py/get_mapped_post.py --project <1|2> --platform facebook
```

The output will give you the `ID` and `Caption`.
Construct the full absolute path for the asset file. For example, if your workspace is `/Users/dsen/Projects/ai-post-maker`:
`/Users/dsen/Projects/ai-post-maker/project-<N>/assets/<ID>.mp4`

Ensure you have the exact absolute path before proceeding.

---

### Step 2: Navigate to Facebook Reels Tab

1.  **Retrieve URL**: Read the `facebook_reels_url` from `project-<N>/grok_prompts.json` under the `config` key.
2.  **Open Page**: Use the `browseros/new_page` tool to open a new tab at that URL.
    - Note the new **Page ID** returned.
3.  **Verify Load**: Call `browseros/take_snapshot` to ensure the page has loaded and the "Reels" tab or "Create reel" button is visible.

---

### Step 3: Initiate Reel Creation

1.  **Click Create**: Identify the element ID for the **"Create reel"** button from the snapshot and click it using `browseros/click`.
2.  **Verify Dialog**: Ensure a file upload dialog or drag-and-drop area appears in the next snapshot.

---

### Step 4: Upload the Video File

1.  **Expose File Input**: Facebook may use hidden file inputs. Run this script to make them targetable:
    ```javascript
    document.querySelectorAll('input[type="file"]').forEach(i => {
      i.style.display = 'block';
      i.style.visibility = 'visible';
      i.style.opacity = '1';
    });
    ```
2.  **Upload**: Call `browseros/upload_file` with the identified file input element ID and the absolute `.mp4` path from Step 1.
3.  **Wait for Progress**: Poll the page every 20-30 seconds using `browseros/evaluate_script` with `document.body.innerText.includes('Your reel is safe to publish!')` until the upload is complete.
4. Take `browseros/take_snapshot` get the id for "Next" button and `browseros/click` with the element id to move to next step.

---

### Step 5: Add Caption and Proceed

1.  **Enter Caption**: Identify the "Describe your reel..." textbox element ID.
2.  **Fill Caption**: Use `browseros/fill` to enter the `Caption` extracted in Step 1.
3.  **Click Next**: Click the **"Next"** button to proceed through the editing steps until you reach the final review screen.

---

### Step 6: STOP — Manual Review

**CRITICAL**: This workflow MUST stop at the final review screen.
1.  Verify the **"Post"** button is visible using `browseros/take_snapshot`.
2.  Wait for human confirmation before proceeding. **DO NOT click "Post" automatically.**

---

### Step 7: Mark Record as Done

Once the post is confirmed as published (manually or after review), update the status in `grok_prompts.json`:

```bash
# Replace <N> with project number and <ID> with the extracted ID
python3 scripts/py/grok_tracker.py --project <N> mark_uploaded <ID> facebook
```

---

### Step 8: Completion

Inform the user that the process is stopped at the review screen and the record has been updated.
