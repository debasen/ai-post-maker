#!/usr/bin/env python3
"""
map_assets.py — Map downloaded Grok video files to prompt IDs.

Usage:
  python3 project-n/map_assets.py --project <1|2> [--extract] [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys
import re
from pathlib import Path
from datetime import datetime

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def get_api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        sys.exit("❌ Set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.")
    return key


def sort_assets_numerically(assets: list[Path]) -> list[Path]:
    def get_num(path: Path):
        match = re.search(r'\((\d+)\)', path.name)
        return int(match.group(1)) if match else 0
    return sorted(assets, key=get_num)


def extract_frame(mp4_path: Path, frame_path: Path) -> bool:
    if frame_path.exists(): return True
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp4_path), "-vframes", "1", "-ss", "0", "-q:v", "2", str(frame_path)],
        capture_output=True
    )
    return frame_path.exists()


def verify_match(frame_path: Path, prompt: str, client, model_name="gemini-1.5-flash") -> tuple[bool, str]:
    from google.genai import types

    img_data = frame_path.read_bytes()
    question = (
        f"Does this frame visually match the following scene description?\n\n"
        f"Scene: {prompt}\n\n"
        f"Reply with exactly: YES or NO, followed by one sentence of reasoning."
    )

    try:
        response = client.models.generate_content(
            model=model_name,
            contents=[
                types.Part.from_bytes(data=img_data, mime_type="image/jpeg"),
                types.Part.from_text(text=question),
            ],
        )
        text = response.text.strip()
        is_match = text.upper().startswith("YES")
        return is_match, text
    except Exception as e:
        return False, str(e)


def update_status(prompt_id, status, project_id, shared_tracker):
    subprocess.run(["python3", str(shared_tracker), "--project", str(project_id), "update_mapping_status", str(prompt_id), status])


# ──────────────────────────────────────────────────────────────────────────────
# Execution
# ──────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=int, required=True, choices=[1, 2], help="Project ID (1 or 2)")
    parser.add_argument("--extract", action="store_true", help="Bulk extract frames from all unmapped videos")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # ffmpeg availability check
    if subprocess.run(["which", "ffmpeg"], capture_output=True).returncode != 0:
        sys.exit("❌ ffmpeg is not installed or not in PATH. Install it via: brew install ffmpeg")

    ROOT_DIR = Path(__file__).parent.parent
    PROJECT_DIR = ROOT_DIR / f"project-{args.project}"
    ASSETS_DIR = PROJECT_DIR / "assets"
    PROCESSING_DIR = ASSETS_DIR / "processing"
    PROCESSING_DIR.mkdir(parents=True, exist_ok=True)
    
    PROMPTS_FILE = PROJECT_DIR / "grok_prompts.json"
    SHARED_TRACKER = ROOT_DIR / "scripts" / "py" / "grok_tracker.py"
    FRAME_EXT = ".jpg"

    if not PROMPTS_FILE.exists():
        sys.exit(f"❌ Prompts file not found: {PROMPTS_FILE}")

    # --- Phase 1: Bulk Extraction ---
    if args.extract:
        print(f"🎞️ Starting bulk frame extraction for Project-{args.project}...")
        unmapped = [f for f in PROCESSING_DIR.glob("*.mp4")]
        for mp4 in unmapped:
            frame = mp4.with_suffix(FRAME_EXT)
            if not frame.exists():
                print(f"  - Extracting: {mp4.name}")
                extract_frame(mp4, frame)
        print("✅ Bulk extraction complete.")
        return

    # --- Phase 2: Mapping ---
    from google import genai
    client = genai.Client(api_key=get_api_key())

    # 1. Load data
    data = json.loads(PROMPTS_FILE.read_text())
    prompts = [p for p in data["prompts"] if p.get("status") == "completed" and "instagram_upload" not in p]
    prompts.sort(key=lambda p: p["id"])

    if not prompts:
        print(f"✅ No prompts pending mapping for Project-{args.project}.")
        return

    print(f"🔍 Mapping {len(prompts)} prompts for Project-{args.project}...")

    for p in prompts:
        pid = p["id"]
        prompt_text = p["prompt"]
        
        # 2. Get next 3 unprocessed images
        all_mp4s = [f for f in PROCESSING_DIR.glob("*.mp4")]
        sorted_mp4s = sort_assets_numerically(all_mp4s)
        lookahead = sorted_mp4s[:3]

        if not lookahead:
            print(f"⚠️ No more video assets found for ID {pid}")
            break

        print(f"\n👉 Checking ID {pid}: '{prompt_text[:60]}...'")
        found_match = False

        for mp4_path in lookahead:
            frame_path = mp4_path.with_suffix(FRAME_EXT)
            extract_frame(mp4_path, frame_path)
            
            print(f"  - Testing {mp4_path.name}...", end=" ", flush=True)
            is_match, reason = verify_match(frame_path, prompt_text, client)
            
            if is_match:
                print(f"YES ✓")
                print(f"    Reason: {reason}")
                
                new_name = f"{pid}.mp4"
                if not args.dry_run:
                    # Move from processing to main assets folder
                    mp4_path.rename(ASSETS_DIR / new_name)
                    frame_path.unlink(missing_ok=True)
                    update_status(pid, "mapped", args.project, SHARED_TRACKER)
                else:
                    print(f"    [Dry Run] Would move to {ASSETS_DIR / new_name}")
                
                found_match = True
                break
            else:
                print(f"NO ✗ ({reason[:50]}...)")

        if not found_match:
            print(f"  ❌ No match in next 3 images for ID {pid}")
            if not args.dry_run:
                update_status(pid, "not-found", args.project, SHARED_TRACKER)

    print("\n✅ Mapping process finished.")

if __name__ == "__main__":
    main()
