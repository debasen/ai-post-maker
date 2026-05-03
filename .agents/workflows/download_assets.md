---
description: Automated Video Asset Download & Mapping (LIFO)
---

# Automated Video Asset Download Workflow

This workflow automatically downloads completed Grok videos from their post URLs and maps them to record IDs in `project-{N}/assets/`. Videos are processed in **LIFO order** (highest ID first).

---

## Prerequisites

- A browser tab logged into Grok (page ID known)
- The project has prompts with `status: "completed"` and valid `video_url`s

---

## Phase 1: Prepare Download Queue

Run the downloader script to get the list of missing videos sorted LIFO:

```bash
python3 scripts/py/grok_asset_downloader.py --project <1|2> queue
```

This outputs a JSON array like:
```json
[
  {
    "id": 99,
    "video_url": "https://grok.com/imagine/post/0a08c1a5-8ea8-4b8d-bd39-d0d274209211",
    "post_url": "https://grok.com/imagine/post/...",
    "prompt": "...",
    "instagram_caption": "..."
  }
]
```

---

## Phase 2: Batch Download Loop

For each item in the queue (starting from the first / highest ID), repeat the following steps.

### Step 2A: Navigate to Video URL

Use `navigate_page` to go to the item's `video_url`:

```javascript
// Tool: navigate_page
{
  "page": <grok_page_id>,
  "action": "url",
  "url": "https://grok.com/imagine/post/<post-id>"
}
```

Wait ~3 seconds for the page to load.

### Step 2B: Verify Video Presence

Inject the downloader helper and check for video:

```javascript
// Tool: evaluate_script
{
  "page": <grok_page_id>,
  "expression": `
    ${await fetch('/Users/dsen/Projects/ai-post-maker/scripts/js/grok_downloader.js').then(r=>r.text())}
    GrokDownloader.checkPage();
  `
}
```

Or inline (if file fetch is unavailable):

```javascript
// Tool: evaluate_script
{
  "page": <grok_page_id>,
  "expression": `
    (() => {
      const video = document.querySelector('video');
      const downloadBtn = document.querySelector('button[aria-label="Download"]');
      return {
        hasVideo: !!video,
        videoSrc: video ? (video.currentSrc || video.src) : null,
        hasDownloadBtn: !!downloadBtn,
        downloadBtnEnabled: downloadBtn ? !downloadBtn.disabled : false,
        url: window.location.href
      };
    })();
  `
}
```

**Expected result:**
- `hasVideo: true`
- `hasDownloadBtn: true`
- `downloadBtnEnabled: true`

If `hasVideo` is false, wait up to 10 seconds and retry once. If still no video, **skip** this item and continue to the next.

### Step 2C: Take Snapshot to Find Download Button

```javascript
// Tool: take_snapshot
{
  "page": <grok_page_id>
}
```

Locate the element ID for the **"Download"** button in the snapshot output.

### Step 2D: Download the Video

Use `download_file` to click the Download button and save directly to the project's assets folder:

```javascript
// Tool: download_file
{
  "page": <grok_page_id>,
  "element": <download_button_element_id>,
  "path": "/Users/dsen/Projects/ai-post-maker/project-<1|2>/assets"
}
```

**Note:** The file will be saved with a Grok-generated name like `grok-video-<uuid>.mp4`.

### Step 2E: Rename to Record ID

After the download completes, rename the file to match the record ID:

```bash
python3 scripts/py/grok_asset_downloader.py --project <1|2> rename \
  "project-<1|2>/assets/<downloaded_filename>.mp4" <record_id>
```

Example:
```bash
python3 scripts/py/grok_asset_downloader.py --project 1 rename \
  "project-1/assets/grok-video-89dc566f-5157-4b5d-ae8f-976485aced78.mp4" 99
```

This will rename the file to `project-1/assets/99.mp4`.

---

## Phase 3: Batch Rename (Alternative / Cleanup)

If multiple videos were downloaded and you want to auto-rename based on UUID matching:

```bash
python3 scripts/py/grok_asset_downloader.py --project <1|2> batch_rename project-<1|2>/assets
```

> ⚠️ **Caveat:** Grok download filenames do NOT reliably contain the post UUID. Explicit per-item rename (Phase 2E) is recommended for accuracy.

---

## Phase 4: Verify Completion

Check stats to confirm all completed prompts have mapped assets:

```bash
python3 scripts/py/grok_asset_downloader.py --project <1|2> stats
```

Expected output:
```json
{
  "project": 1,
  "total_prompts": 120,
  "completed": 95,
  "downloaded": 95,
  "missing": 0,
  "missing_ids": []
}
```

---

## Repeatability Commands

| Command | Purpose |
|---------|---------|
| `python3 scripts/py/grok_asset_downloader.py --project <1\|2> queue` | Get LIFO-sorted list of missing videos |
| `python3 scripts/py/grok_asset_downloader.py --project <1\|2> stats` | Show download progress statistics |
| `python3 scripts/py/grok_asset_downloader.py --project <1\|2> rename <src> <id>` | Rename a downloaded file to `<id>.mp4` |
| `python3 scripts/py/grok_asset_downloader.py --project <1\|2> list_downloaded` | List all mapped asset files |

---

## Integration with Mapping Workflow

After downloading, you may still need to run the mapping workflow to set `asset` status:

```bash
python3 scripts/py/grok_tracker.py --project <1|2> update_mapping_status <id> mapped
```

Or use the visual mapping workflow (`.agents/workflows/map_assets_v2.md`) if order verification is needed.

---

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Download button disabled | The video may still be generating. Wait and retry. |
| No video element found | The `video_url` may point to an image-only post. Skip and check `post_url` instead. |
| File already exists at destination | The rename command automatically backs up the existing file. |
| 403 on direct video URL | Expected — Grok requires session cookies. Always download via the browser. |
| Download filename doesn't match UUID | Use explicit `rename` with the correct record ID instead of `batch_rename`. |
