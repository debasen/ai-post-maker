---
description: Grok Home Automation
---

# Grok Image & Video Generation Rule Book

This document serves as the standard operating procedure for generating assets on Grok. Use this guide to ensure consistency across all tasks.

## Phase 1: Preparation

1.  **Identify Prompt**: Run `python3 scripts/py/grok_tracker.py --project <ID> get_next` to retrieve the next pending prompt and its associated `<ID>`.
2.  **Verify Status**: The script will automatically return the first available `pending` record. Ensure you have the correct `<ID>` for subsequent steps.

## Phase 2: Platform Navigation

1.  **Open Grok**: Navigate to `https://grok.com/imagine`.

## Phase 3: Image Generation

1.  **Identify Input**: Use `browseros/evaluate_script` to get exact coordinates of the input area (usually a `div` with the placeholder "Type to imagine").
    - **Example expression:**
      ```javascript
      (function() {
        const el = document.querySelector('div[contenteditable="true"]');
        if (el) {
          const rect = el.getBoundingClientRect();
          return JSON.stringify({
            x: rect.left + rect.width / 2,
            y: rect.top + rect.height / 2,
            found: true
          });
        }
        return JSON.stringify({ found: false });
      })()
      ```
    - **Parameters:** `"page": 75`

2.  **Enter Prompt**: Type the exact prompt text retrieved in Phase 1 into the input area. Call `browseros/type_at` with `x`, `y`, and `text`.
    - **Example parameters:**
      ```json
      {
        "clear": true,
        "page": 75,
        "text": "Ultra realistic highly detailed image of a deep bowl of Vietnamese beef pho. The broth is crystal clear but rich in color. Thin slices of rare beef are turning brown as they cook in the hot liquid. Fresh Thai basil, lime wedges, dynamic action shot with steam. output 9:16 portrait",
        "x": 720,
        "y": 679
      }
      ```
3.  **Trigger Generation**: Press `Enter` using `browseros/press_key`.

## Phase 4: Video Generation

1.  **Select Image (Open Detailed Page)**: Once images appear, you must open the detailed view.
    - **Primary Method**: Call `browseros/take_snapshot` to get the first 'link' element id. Then call `browseros/click` with the element id. DON'T click on "Make video" element [41321] directly.
    - **Fallback Method**: Click the preferred "Generated image" (use the `evaluate_script` below to find coordinates).

    - **Example expression for Fallback Method:**
      ```javascript
      (function() {
        const el = document.querySelector('img[alt="Generated image"]');
        if (el) {
          const rect = el.getBoundingClientRect();
          return JSON.stringify({
            x: rect.left + rect.width / 2,
            y: rect.top + rect.height / 2,
            found: true
          });
        }
        return JSON.stringify({ found: false });
      })()
      ```
    - **Then use `browseros/click_at` with `x`, `y`:**
      ```json
      {
        "button": "left",
        "clickCount": 1,
        "page": 80,
        "x": 214,
        "y": 375
      }
      ```
2.  **Animate**: Click the **"Make video"** button in the detail view.

## Phase 5: Monitoring & Validation

1.  **Track Progress**: Monitor the percentage indicator (e.g., "Generating X%") in 20 sec intervals using `browseros/take_snapshot`.
2.  **Verify Completion**: Wait for the "Thumbnail" or "Download" buttons to become active, signifying the video is ready.

## Phase 6: Asset Management

1.  **Locate Download Button**:
    - Call `browseros/take_snapshot` on the active page.
    - Identify the interactive element with `aria-label="Download"`.
2.  **Download the File**:
    - Call `browseros/download_file` with the identified element ID.
    - Set `path` to the project destination directory (Replace N): `/Users/dsen/Projects/ai-post-maker/project-<N>/assets/current/`.
3.  **Rename**:
    - Run: `python3 scripts/py/grok_video_downloader.py --project <N> process_download project-<N>/assets/current/ <ID>`
    - This command finds the most-recent file in the destination directory and renames it to `<ID>.mp4`.
4.  **Verify**:
    - Confirm the file exists at `project-<N>/assets/current/<ID>.mp4` with non-zero size.

## Phase 7: Recording & Tracking

1.  **Update Tracker**: Run `python3 scripts/py/grok_tracker.py --project <ID> complete <ID> "<VIDEO_URL>" "<POST_URL>"` to mark the task as complete and record the URLs. (Use `grok_tracker_v3.py` for Project 3).

---

**Note**: Element IDs (e.g., `[8641]`) and coordinates are dynamic and should be verified via `take_snapshot` at the start of each session.
