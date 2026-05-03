#!/usr/bin/env python3
"""
move_current_assets.py — Move assets from project-<N>/assets/current/ to project-<N>/assets/
and update the corresponding prompt record's asset status to "mapped".

Usage:
  python3 scripts/py/move_current_assets.py --project <1|2> [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def get_project_path(project_id: int) -> Path:
    """Resolve the path to grok_prompts.json in the project folder."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    return repo_root / f"project-{project_id}" / "grok_prompts.json"


def load_prompts(project_path: Path) -> list[dict]:
    """Load prompts from grok_prompts.json."""
    if not project_path.exists():
        print(f"❌ Project file not found: {project_path}")
        sys.exit(1)
    with open(project_path, "r") as f:
        data = json.load(f)
    return data.get("prompts", [])


def move_assets(project_id: int, dry_run: bool = False) -> None:
    """Move assets from current/ to assets/ and update mapping status."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    project_dir = repo_root / f"project-{project_id}"
    assets_dir = project_dir / "assets"
    current_dir = assets_dir / "current"
    tracker_script = script_dir / "grok_tracker.py"

    if not current_dir.exists():
        print(f"⚠️  Current folder does not exist: {current_dir}")
        return

    mp4_files = sorted([f for f in current_dir.glob("*.mp4")])

    if not mp4_files:
        print(f"✅ No assets to move in project-{project_id}/assets/current/")
        return

    prompts = load_prompts(get_project_path(project_id))
    valid_ids = {str(p["id"]) for p in prompts}

    print(f"🚀 Moving {len(mp4_files)} asset(s) for project-{project_id}...")
    if dry_run:
        print("   [DRY RUN — no files will be moved]")

    for mp4_file in mp4_files:
        prompt_id = mp4_file.stem
        dest_path = assets_dir / mp4_file.name

        if not prompt_id.isdigit():
            print(f"  ⚠️  Skipping invalid filename: {mp4_file.name}")
            continue

        if prompt_id not in valid_ids:
            print(f"  ⚠️  Skipping — prompt ID {prompt_id} not found in grok_prompts.json")
            continue

        if dest_path.exists():
            print(f"  ⚠️  Skipping — file already exists in assets/: {mp4_file.name}")
            continue

        if dry_run:
            print(f"  [Dry Run] Would move {mp4_file.name} → assets/ and mark ID {prompt_id} as mapped")
            continue

        # Move file
        mp4_file.rename(dest_path)
        print(f"  ✅ Moved {mp4_file.name} → assets/")

        # Update tracker status
        result = subprocess.run(
            ["python3", str(tracker_script), "--project", str(project_id), "update_mapping_status", prompt_id, "mapped"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print(f"     Marked ID {prompt_id} as mapped")
        else:
            print(f"     ❌ Failed to update status for ID {prompt_id}: {result.stderr.strip() or result.stdout.strip()}")

    print("\n✅ Done.")


def main():
    parser = argparse.ArgumentParser(
        description="Move assets from current/ to assets/ and update mapping status"
    )
    parser.add_argument("--project", type=int, required=True, choices=[1, 2, 3, 4], help="Project ID (1, 2, 3, or 4)")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without moving files")
    args = parser.parse_args()

    move_assets(args.project, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
