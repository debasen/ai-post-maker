#!/usr/bin/env python3
"""
grok_asset_downloader.py — Automated video asset download queue & file manager.

Usage:
  python3 shared/grok_asset_downloader.py --project <1|2> queue [--lifo]
  python3 shared/grok_asset_downloader.py --project <1|2> list_downloaded
  python3 shared/grok_asset_downloader.py --project <1|2> rename <source_path> <record_id>
  python3 shared/grok_asset_downloader.py --project <1|2> batch_rename <download_dir>
  python3 shared/grok_asset_downloader.py --project <1|2> stats
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime


def get_project_path(project_id: int) -> Path:
    """Resolve project directories."""
    repo_root = Path(__file__).parent.parent
    return repo_root / f"project-{project_id}"


def load_prompts(project_id: int) -> list[dict]:
    """Load grok_prompts.json for a project."""
    path = get_project_path(project_id) / "grok_prompts.json"
    if not path.exists():
        print(json.dumps({"error": f"Prompts file not found: {path}"}))
        sys.exit(1)
    with open(path, "r") as f:
        data = json.load(f)
    return data.get("prompts", [])


def get_existing_asset_ids(project_id: int) -> set[int]:
    """Return set of record IDs that already have mapped MP4 files."""
    assets_dir = get_project_path(project_id) / "assets"
    if not assets_dir.exists():
        return set()

    ids = set()
    for f in assets_dir.glob("*.mp4"):
        name = f.stem
        # Only count properly mapped files (pure numeric ID)
        if name.isdigit():
            ids.add(int(name))
    return ids


def get_download_queue(project_id: int, lifo: bool = True) -> list[dict]:
    """Return list of completed prompts missing their mapped MP4 asset."""
    prompts = load_prompts(project_id)
    existing_ids = get_existing_asset_ids(project_id)

    missing = []
    for p in prompts:
        if p.get("status") != "completed":
            continue
        pid = p.get("id")
        if pid in existing_ids:
            continue

        video_url = p.get("video_url")
        # Skip entries without a valid Grok video URL
        if not video_url or "grok.com" not in video_url:
            continue

        missing.append({
            "id": pid,
            "video_url": video_url,
            "post_url": p.get("post_url"),
            "prompt": p.get("prompt", ""),
            "instagram_caption": p.get("instagram_caption", ""),
        })

    # Sort by ID
    missing.sort(key=lambda x: x["id"], reverse=lifo)
    return missing


def rename_downloaded_file(project_id: int, source_path: str, record_id: int) -> dict:
    """Rename a downloaded Grok video file to <record_id>.mp4 in the project's assets."""
    assets_dir = get_project_path(project_id) / "assets"
    assets_dir.mkdir(parents=True, exist_ok=True)

    src = Path(source_path)
    if not src.exists():
        return {"success": False, "error": f"Source file not found: {source_path}"}

    dest = assets_dir / f"{record_id}.mp4"
    if dest.exists():
        # Backup existing file
        backup = dest.with_suffix(f".mp4.backup.{datetime.now().strftime('%Y%m%d%H%M%S')}")
        dest.rename(backup)

    src.rename(dest)
    return {"success": True, "id": record_id, "path": str(dest)}


def batch_rename_downloads(project_id: int, download_dir: str) -> list[dict]:
    """
    Auto-rename downloaded grok-video-*.mp4 files by matching post_id in filename
    to record IDs. Requires that the Grok download filename contains a UUID that
    matches the post ID from the video_url.
    
    NOTE: Grok download filenames do NOT reliably match post IDs, so this is
    best-effort. Prefer explicit rename per item.
    """
    prompts = load_prompts(project_id)
    existing_ids = get_existing_asset_ids(project_id)
    download_path = Path(download_dir)

    results = []
    # Build a map of post_id -> record_id
    post_id_map = {}
    for p in prompts:
        if p.get("status") != "completed":
            continue
        pid = p.get("id")
        if pid in existing_ids:
            continue
        video_url = p.get("video_url", "")
        match = re.search(r"post/([a-f0-9\-]+)", video_url)
        if match:
            post_id_map[match.group(1)] = pid

    for f in sorted(download_path.glob("grok-video-*.mp4")):
        # Extract UUID from filename: grok-video-<uuid>.mp4
        match = re.search(r"grok-video-([a-f0-9\-]+)\.mp4", f.name)
        if match:
            file_uuid = match.group(1)
            if file_uuid in post_id_map:
                record_id = post_id_map[file_uuid]
                result = rename_downloaded_file(project_id, str(f), record_id)
                results.append(result)
            else:
                results.append({"success": False, "file": f.name, "error": "UUID not matched to any record"})
        else:
            results.append({"success": False, "file": f.name, "error": "Could not extract UUID"})

    return results


def list_downloaded_files(project_id: int) -> list[dict]:
    """List all properly mapped MP4 files in the project's assets."""
    assets_dir = get_project_path(project_id) / "assets"
    if not assets_dir.exists():
        return []

    files = []
    for f in sorted(assets_dir.glob("*.mp4")):
        if f.stem.isdigit():
            files.append({
                "id": int(f.stem),
                "filename": f.name,
                "size_bytes": f.stat().st_size,
            })
    return files


def get_stats(project_id: int) -> dict:
    """Return download statistics for a project."""
    prompts = load_prompts(project_id)
    completed = [p for p in prompts if p.get("status") == "completed"]
    existing = get_existing_asset_ids(project_id)
    missing = [p for p in completed if p.get("id") not in existing]

    return {
        "project": project_id,
        "total_prompts": len(prompts),
        "completed": len(completed),
        "downloaded": len(existing),
        "missing": len(missing),
        "missing_ids": [p["id"] for p in missing],
    }


def main():
    parser = argparse.ArgumentParser(description="Grok Asset Downloader Manager")
    parser.add_argument("--project", type=int, required=True, choices=[1, 2], help="Project ID")
    parser.add_argument("command", choices=[
        "queue", "list_downloaded", "rename", "batch_rename", "stats"
    ], help="Command to run")
    parser.add_argument("args", nargs="*", help="Additional arguments for the command")
    parser.add_argument("--lifo", action="store_true", default=True, help="Sort queue LIFO (default)")
    parser.add_argument("--fifo", action="store_true", help="Sort queue FIFO instead")

    args = parser.parse_args()
    lifo = not args.fifo

    if args.command == "queue":
        queue = get_download_queue(args.project, lifo=lifo)
        print(json.dumps(queue, indent=2))

    elif args.command == "list_downloaded":
        files = list_downloaded_files(args.project)
        print(json.dumps(files, indent=2))

    elif args.command == "rename":
        if len(args.args) < 2:
            print(json.dumps({"error": "Usage: rename <source_path> <record_id>"}))
            sys.exit(1)
        source_path = args.args[0]
        try:
            record_id = int(args.args[1])
        except ValueError:
            print(json.dumps({"error": "record_id must be an integer"}))
            sys.exit(1)
        result = rename_downloaded_file(args.project, source_path, record_id)
        print(json.dumps(result))

    elif args.command == "batch_rename":
        if len(args.args) < 1:
            print(json.dumps({"error": "Usage: batch_rename <download_dir>"}))
            sys.exit(1)
        results = batch_rename_downloads(args.project, args.args[0])
        print(json.dumps(results, indent=2))

    elif args.command == "stats":
        stats = get_stats(args.project)
        print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
