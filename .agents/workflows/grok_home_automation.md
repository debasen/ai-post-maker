---
description: Advanced end-to-end automation for generating videos on Grok based on browser_os.md rules. Requires --project <ID> argument.
---

# Grok Home Automation Workflow

This workflow automates the process of generating image-to-video assets on Grok, following the standard operating procedures defined in `browser_os.md`.

## Phase 1: Preparation

1. **Identify Prompt**: Run the following command to retrieve the next pending record.
   ```bash
   python3 scripts/py/grok_tracker.py --project <PROJECT_ID> get_next
   ```
   **Extract**: `id`, `prompt`.
   If it returns `{"error": "..."}` → **Exit**.

## Phase 2: Platform Navigation

1. **Open Grok Imagine**: Use `browseros_new_page` or `browseros_navigate_page` to go to:
   ```
   https://grok.com/imagine
   ```

## Phase 3: Generation Process

1. **Input Prompt**: 
   - Call `browseros_take_snapshot` to identify the `contenteditable` input area (placeholder: "Type to imagine").
   - Use `browseros_fill` to enter the `prompt` text.
2. **Trigger Generation**: Use `browseros_press_key` with `key="Enter"` on the input area.
3. **Select Image**: 
   - Wait for images to appear.
   - Call `browseros_take_snapshot` and click the first "Generated image" element.
4. **Animate**: 
   - In the detail view, call `browseros_take_snapshot`.
   - Click the **"Make video"** button.

## Phase 4: Monitoring & Validation

1. **Track Progress**: 
   - Monitor the page for the percentage indicator (e.g., "Generating X%").
   - Wait in 20-second intervals using `sleep 20`.
2. **Verify Completion**: 
   - Wait for the "Download" button (aria-label="Download") to become active.

## Phase 5: Asset Management

1. **Download**:
   - Call `browseros_take_snapshot`.
   - Call `browseros_download_file` on the element with `aria-label="Download"`.
   - **Path**: `/Users/dsen/Projects/ai-post-maker/project-<PROJECT_ID>/assets/current/`
2. **Rename & Process**:
   - Run the following command:
     ```bash
     python3 scripts/py/grok_video_downloader.py --project <PROJECT_ID> process_download project-<PROJECT_ID>/assets/current/ <ID>
     ```
3. **Verify**:
   - Ensure the file `project-<PROJECT_ID>/assets/current/<ID>.mp4` exists and is valid.

## Phase 6: Recording & Tracking

1. **Update Tracker**:
   - Extract the current URL as `postUrl`.
   - (Optional) Identify the video source URL as `videoUrl`.
   - Run the completion command:
     ```bash
     python3 scripts/py/grok_tracker.py --project <PROJECT_ID> complete <ID> "<VIDEO_URL>" "<POST_URL>"
     ```
