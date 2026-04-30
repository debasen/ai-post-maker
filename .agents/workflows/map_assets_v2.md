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

### Phase 2: Iterative Mapping
Perform this loop for each pending prompt entry.

1.  **Identify Next Candidate**: 
    Run the tracker to get the ID and Prompt text for the next item missing mapping.
    ```bash
    python3 scripts/py/grok_tracker.py --project <1|2> get_next_to_map
    ```

2.  **Order Available Assets**: 
    Identify the 3 oldest available assets in `assets/processing/`.
    ```bash
    cd project-<1|2>/assets/processing && for f in *.mp4; do echo "$(stat -f %m "$f" 2>/dev/null) | $f"; done | sort -n | head -3
    ```

3.  **Visual Verification**:
    *   Open the `.jpg` frames for the 3 candidates using `view_file`.
    *   Compare the visuals against the prompt description.

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

## 🚀 Repeatability Scripts

| Script Command | Purpose |
|---|---|
| `python3 project-2/map_assets.py --project <1\|2> --extract` | Bulk generate preview frames in `assets/processing/`. |
| `python3 scripts/py/grok_tracker.py --project <1\|2> get_next_to_map` | Find the next prompt needing a video mapping. |
| `python3 scripts/py/grok_tracker.py --project <1\|2> update_mapping_status <id> <mapped\|not-found>` | Manually update the status. |

## 💡 Mapping Logic Reference
- **Lookahead 3**: Always check a window of 3 assets to account for skips or mismatched order.
- **Source of Truth**: `instagram_upload` field in `project-{N}/grok_prompts.json`.
- **Sorting**: Assets are sorted by modification time (`stat -f %m`) to reflect download order (oldest first).
