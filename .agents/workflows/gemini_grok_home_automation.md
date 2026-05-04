---
description: Gemini Nano Banana -> Grok Home Automation
---

# Gemini Nano Banana Image + Grok Video Generation Rule Book

This document serves as the standard operating procedure for generating images on Gemini Nano Banana and then passing them to Grok for watermark removal and video generation. Use this guide to ensure consistency across all tasks.

## Phase 1: Preparation

1.  **Identify Prompt**: Run `python3 scripts/py/grok_tracker.py --project <ID> get_next` to retrieve the next pending prompt and its associated `<ID>`.
2.  **Verify Status**: The script will automatically return the first available `pending` record. Ensure you have the correct `<ID>` for subsequent steps.

## Phase 2: Image Generation (Gemini Nano Banana)

1.  **Open Gemini Nano Banana**: Navigate to `https://gemini.google.com/gem/6c035512f48a`.
    - **Foreground Requirement**: Ensure this page stays in the foreground. If it is not the active/visible tab, use `browseros/show_page` to bring it to the foreground.

2.  **Locate & Enter Prompt**: Gemini's input box requires specific event dispatches to enable the Send button. Do not use `type_at` or `fill`. Use `browseros/evaluate_script` to inject the prompt text, dispatch the necessary React events, and click the send button simultaneously:
    - **Example expression:**
      ```javascript
      (function() {
        const el = document.querySelector('textarea, div[contenteditable="true"]');
        if (el) {
          // Replace YOUR_PROMPT_HERE with the exact prompt from Phase 1
          el.innerText = "YOUR_PROMPT_HERE";
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          
          setTimeout(() => {
              const btn = document.querySelector('button[aria-label="Send message"]');
              if (btn && !btn.disabled) {
                  btn.click();
              }
          }, 500);
          return "Set text and clicked";
        }
        return "Not found";
      })()
      ```

3.  **Wait for Image Generation**: Wait for the generated image to appear in the chat. Use `browseros/take_snapshot` periodically to check for completion.
    - **Wait for Readiness**: Once the image is visible, wait an additional 5-10 seconds before attempting to download to ensure the asset is fully processed on the server side.

4.  **Download the Image**:
    - Use `browseros/search_dom` with query `"Download full size image"` to find the button and get its element ID.
    - Call `browseros/download_file` with the element ID and set `path` to `/Users/dsen/Projects/ai-post-maker/scratch`. This downloads the file directly into the scratch folder, avoiding the need to move it from `~/Downloads`.

## Phase 3: Watermark Removal (Grok)

1.  **Open Grok**: Navigate to `https://grok.com/imagine`.
    - **Foreground Requirement**: Ensure this page stays in the foreground. If it is not the active/visible tab, use `browseros/show_page` to bring it to the foreground.

2.  **Attach Image**:
    - Use `browseros/evaluate_script` to make the hidden file input visible:
      ```javascript
      (function() {
        const el = document.querySelector('input[type="file"]');
        if (el) {
          el.style.display = 'block';
          el.style.visibility = 'visible';
          el.style.opacity = '1';
          el.style.position = 'fixed';
          el.style.top = '0';
          el.style.left = '0';
          el.style.zIndex = '9999';
          return "Visible";
        }
        return "Not found";
      })()
      ```
    - Call `browseros/take_snapshot` to find the element ID of the newly visible button "Choose Files".
    - Call `browseros/upload_file` with that ID and the image path.

3.  **Enter Static Prompt**: 
    - Use `browseros/evaluate_script` to set the text and trigger events to ensure the "Submit" button enables:
      ```javascript
      (function() {
        const el = document.querySelector('div[contenteditable="true"]');
        if (el) {
          el.innerText = "Remove the watermark and don't change anything else";
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return "Set text";
        }
        return "Not found";
      })()
      ```

4.  **Submit**: Grok's "Submit" button does not reliably respond to standard clicks. Use `browseros/evaluate_script` to click it:
      ```javascript
      (function() {
        const submitBtn = document.querySelector('button[aria-label="Submit"], button[title="Submit"]') || 
                          Array.from(document.querySelectorAll('button')).find(btn => btn.innerText.trim() === 'Submit');
        if (submitBtn && !submitBtn.disabled) {
          submitBtn.click();
          return "Clicked Submit";
        }
        return "Not found or disabled";
      })()
      ```

5.  **Wait for Detail Page**: Grok will automatically navigate to the detailed view page. Ensure this page stays in the foreground; if it loses focus, use `browseros/show_page`.
6.  **Select 1st Image**: Grok generates two images during image generation. Select the first image (often labeled "Thumbnail 2") before proceeding to video generation. Use `browseros/evaluate_script`:
      ```javascript
      (function() {
        const firstImage = document.querySelector('img[alt="Thumbnail 2"]'); 
        if (firstImage) {
          firstImage.click();
          return "Clicked Thumbnail 2";
        }
        return "Thumbnail 2 not found";
      })()
      ```

## Phase 4: Video Generation

1.  **Animate**: Click the **"Make video"** button in the detail view using `browseros/evaluate_script`:
      ```javascript
      (function() {
        const btn = Array.from(document.querySelectorAll('button')).find(btn => btn.innerText.trim() === 'Make video');
        if (btn && !btn.disabled) {
          btn.click();
          return "Clicked Make video";
        }
        return "Not found";
      })()
      ```

## Phase 5: Monitoring & Validation

1.  **Track Progress**: Monitor the percentage indicator in 30-60 sec intervals.
2.  **Verify Completion**: Wait for the "Download" button to become active.

## Phase 6: Asset Management

1.  **Download the File**:
    - **Wait for Readiness**: Once the "Download" button becomes active, wait 10-15 seconds to ensure the final video file is stabilized and ready for transfer.
    - Use `browseros/search_dom` with query `"Download"` to find the button and get its element ID.
    - Call `browseros/download_file` with the element ID and set `path` to `/Users/dsen/Projects/ai-post-maker/scratch`. This downloads the file directly into the scratch folder.

2.  **Rename and Move**:
    - Run the following command to move and rename the file from `scratch/` to the project's assets directory:
      `python3 scripts/py/grok_video_downloader.py --project <N> process_download scratch <ID>`

## Phase 7: Recording & Tracking

1.  **Update Tracker**: Run `python3 scripts/py/grok_tracker.py --project <ID> complete <ID> "N/A" "N/A"` (or provide URLs if available).

## Phase 8: Cleanup

1.  **Close Tabs**: Once the task is complete and tracked, close the Gemini and Grok tabs to keep the browser organized.
    - Use `browseros/list_pages` to identify the correct page IDs.
    - Call `browseros/close_page` for each tab.

---

**Key Discoveries & Improvements:**
- **Clipboard Reliability**: Pasting images into Grok via `Meta+V` is unreliable; downloading and uploading via a hidden input fix is the robust alternative.
- **Button Activation**: Grok's "Submit" button often remains disabled after programmatic typing; use `evaluate_script` to dispatch `input` and `change` events.
- **Hidden Input Fix**: The file input in Grok is hidden and doesn't appear in snapshots. Making it visible via JS allows automation to find its element ID.
- **Monitoring Intervals**: Video generation can be slow; 30-60 second intervals are more efficient than 20 seconds.
