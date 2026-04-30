# Issues Found During `map_assets_v2.md` Workflow Run — Project 2

**Run Date:** 2026-04-30
**Workflow:** `.agents/workflows/map_assets_v2.md`
**Project:** `project-2`

---

## Summary

The mapping workflow was executed manually for Project 2. Phase 1 (frame extraction) and Phase 2 (iterative mapping) completed, resulting in **5 successful mappings** and **10 prompts marked as `not-found`**. Phase 3 (cleanup) is pending.

However, several structural and logic issues were identified during the run that should be addressed to prevent failures in automated or future runs.

---

## Issue 1: Critical — `map_assets.py` References Non-Existent Tracker Path

### Problem
`project-2/map_assets.py` (line 84) references:
```python
SHARED_TRACKER = ROOT_DIR / "shared" / "grok_tracker.py"
```

But the actual tracker script exists at:
```
scripts/py/grok_tracker.py
```

There is **no `shared/` directory** in the repository. If `map_assets.py` is run in mapping mode (without `--extract`), any attempt to call `update_status()` will fail because the subprocess target does not exist.

### Impact
- The automated `map_assets.py` script is **non-functional** for the mapping phase.
- Users must fall back to manual tracker commands or fix the path first.

### Suggested Fix
Update line 84 in `project-2/map_assets.py`:
```python
# OLD (broken)
SHARED_TRACKER = ROOT_DIR / "shared" / "grok_tracker.py"

# NEW (correct)
SHARED_TRACKER = ROOT_DIR / "scripts" / "py" / "grok_tracker.py"
```

Verify the same fix is needed in `project-1/map_assets.py` if it exists.

---

## Issue 2: High — 11 Orphaned Videos Remain in `assets/processing/`

### Problem
After all mappable prompts were processed, **11 videos remain** in `project-2/assets/processing/`:

```
ecfd71b1-edfb-4d5c-a325-e6156d921e05.mp4
grok-video-89dc566f-5157-4b5d-ae8f-976485aced78.mp4
grok-video-89dc566f-5157-4b5d-ae8f-976485aced78 (2).mp4
...(8 more)
grok-video-fcb72a59-5682-47b4-b1dc-a3de4e929940.mp4
```

These videos have **no corresponding `completed` prompts without an `instagram_upload` field**.

### Root Cause Analysis
Possible explanations:
1. **Already mapped in prior runs**: Some prompts already have `instagram_upload: "mapped"` or `"done"`, and their videos may have been re-downloaded or duplicated.
2. **Pending prompts**: Some videos may belong to prompts with `status: "pending"` (IDs 97+ in `grok_prompts.json`), which are not yet eligible for mapping.
3. **Stale downloads**: Some videos may be failed/moderated downloads that were never cleaned up.

### Impact
- Wasted disk space.
- Future mapping runs will re-extract frames for these orphaned videos.
- Manual visual inspection time is spent on videos that may never be mappable.

### Suggested Fix
1. **Add a reconciliation step** to the workflow: after mapping, compare remaining videos against `video_url` fields in `grok_prompts.json`.
2. **Move orphaned videos** to an `assets/orphaned/` directory instead of leaving them in `processing/`.
3. **Update `map_assets.py --extract`** to skip videos that already have a matching prompt ID in the `assets/` folder.

---

## Issue 3: Medium — No `ffmpeg` Availability Check

### Problem
`map_assets.py` calls `ffmpeg` directly via `subprocess.run()` without checking if it is installed:
```python
subprocess.run(
    ["ffmpeg", "-y", "-i", str(mp4_path), "-vframes", "1", "-ss", "0", "-q:v", "2", str(frame_path)],
    capture_output=True
)
```

If `ffmpeg` is missing, the command silently fails (frame is not created) and `extract_frame()` returns `False`, which may cascade into mapping failures.

### Impact
- Silent failure on systems without ffmpeg.
- No actionable error message for the user.

### Suggested Fix
Add an upfront check in `main()`:
```python
if subprocess.run(["which", "ffmpeg"], capture_output=True).returncode != 0:
    sys.exit("❌ ffmpeg is not installed or not in PATH. Install it via: brew install ffmpeg")
```

---

## Issue 4: Medium — Tracker Logic Skips Previously `not-found` Prompts

### Problem
`grok_tracker.py`'s `get_next_to_map()` only returns prompts where:
```python
item.get("status") == "completed" and "instagram_upload" not in item
```

Once a prompt is marked `"not-found"`, it is **never retried** even if new videos are downloaded later that might match it.

### Impact
- If a video is downloaded after a prompt was marked `not-found`, there is no automated way to map it.
- Users must manually clear the `instagram_upload` field to retry.

### Suggested Fix
Add a `--retry-not-found` flag to `grok_tracker.py` that also considers prompts with `instagram_upload == "not-found"`:
```python
def get_next_to_map(file_path, retry_not_found=False):
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    for item in prompts:
        if item.get("status") == "completed":
            if "instagram_upload" not in item:
                print(json.dumps(item))
                return
            if retry_not_found and item.get("instagram_upload") == "not-found":
                print(json.dumps(item))
                return
    print(json.dumps({"error": "No prompts to map"}))
```

---

## Issue 5: Low — Frame Extraction Re-Runs on Already-Mapped Videos

### Problem
The `--extract` flag in `map_assets.py` processes **all** `.mp4` files in `processing/`, including videos that may already be mapped or orphaned.

### Impact
- Wasted CPU/time re-extracting frames for videos that will never be mapped.

### Suggested Fix
Skip extraction for videos whose filename (or a hash) already appears in the `assets/` directory or whose prompt ID is already mapped.

---

## Mapping Results

| Prompt ID | Status | Matched Video |
|---|---|---|
| 80 | **mapped** | `710c0fdd...` (alpine ski chalet) |
| 81 | not-found | — |
| 82 | **mapped** | `6f436e88...` (NYC rooftop warehouse) |
| 83 | **mapped** | `grok-video... (1)` (tropical treehouse) |
| 84 | not-found | — |
| 85 | not-found | — |
| 86 | not-found | — |
| 87 | not-found | — |
| 88 | not-found | — |
| 89 | not-found | — |
| 90 | not-found | — |
| 91 | not-found | — |
| 92 | not-found | — |
| 93 | not-found | — |
| 94 | **mapped** | `grok-video... (10)` (penthouse bedroom) |
| 95 | **mapped** | `grok-video... (13)` (forest stream) |
| 96 | **mapped** | `grok-video... (12)` (Bangkok night market) |

**Final tally:** 5 mapped, 10 not-found, 0 remaining to map.

---

## Action Items

| Priority | Action | Owner |
|---|---|---|
| Critical | Fix `SHARED_TRACKER` path in `map_assets.py` | Dev |
| High | Reconcile orphaned videos in `processing/` | Dev/Ops |
| Medium | Add `ffmpeg` check to `map_assets.py` | Dev |
| Medium | Add `--retry-not-found` to tracker | Dev |
| Low | Skip already-mapped videos during extraction | Dev |
