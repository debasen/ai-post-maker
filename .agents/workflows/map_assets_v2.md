---
description: Mapping Video Assets
---

# Mapping Video Assets Skill (Agent-First)

This skill allows an AI agent to map video files in `project-{N}/assets/processing/` to their prompt IDs in `grok_prompts.json` using visual verification. Mapped files are moved to `project-{N}/assets/`.

---

## 🛠️ End-to-End Steps

### Phase 1: One-Time Setup (Bulk Extraction)
Ensure all downloaded videos in `assets/processing/` have a frame extracted for preview. 

// turbo
```bash
python3 project-2/map_assets.py --project <1|2> --extract
```

### Phase 2: Mapping Loop
Perform this loop for each pending prompt entry.

1.  **Get Next Prompt**:
    ```bash
    python3 scripts/py/grok_tracker.py --project <1|2> get_next_to_map
    ```

2.  **Order Available Assets**: 
    Identify the 3 oldest available assets (the one with no suffix, then `(1)`, `(2)`, etc.).
    ```bash
    cd project-<1|2>/assets/processing && ls grok-video-*.mp4 | sort -V | head -3
    ```

3.  **Visual Verification**:
    Use the `map_assets.py` script to verify the first 3 unmapped assets against the prompt.
    ```bash
    python3 project-2/map_assets.py --project <1|2>
    ```

4.  **Execute Mapping**:
    *   **If Match Found (e.g., File X matches ID 7)**:
        *   Rename and Move video: `mv "project-<1|2>/assets/processing/File X.mp4" "project-<1|2>/assets/7.mp4"`
        *   Delete frame: `rm "project-<1|2>/assets/processing/File X.jpg"`
        *   Update Status: `python3 scripts/py/grok_tracker.py --project <1|2> update_mapping_status 7 mapped`
    *   **If No Match Found (after checking all 3)**:
        *   Update Status: `python3 scripts/py/grok_tracker.py --project <1|2> update_mapping_status 7 not-found`

### Phase 3: Cleanup
Once mapping is finished, remove any leftover frame files in the processing directory.

// turbo
```bash
rm project-<1|2>/assets/processing/*.jpg
```

---

## 🛠️ Tool Reference

| Script Command | Purpose |
|---|---|
| `python3 project-2/map_assets.py --project <1\|2> --extract` | Bulk generate preview frames in `assets/processing/`. |
| `python3 scripts/py/grok_tracker.py --project <1\|2> get_next_to_map` | Find the next prompt needing a video mapping. |
| `python3 scripts/py/grok_tracker.py --project <1\|2> update_mapping_status <id> <mapped\|not-found>` | Manually update the `asset` field. |

## 💡 Mapping Logic Reference
- **Lookahead 3**: Always check a window of 3 assets to account for skips or mismatched order.
- **Source of Truth**: `asset` field in `project-{N}/grok_prompts.json`.
- **Sorting**: Assets are sorted by the numerical suffix in the filename to reflect download order. The original file (no suffix) is processed first, followed by `(1)`, `(2)`, etc.
