import os
import shutil
import time
import json
import argparse
from pathlib import Path

def process_download(project_id, download_dir, record_id):
    """
    Finds the most recently modified file in download_dir, 
    moves and renames it to <record_id>.mp4 in the project's assets/current directory.
    """
    download_path = Path(download_dir)
    if not download_path.exists() or not download_path.is_dir():
        return {"success": False, "error": f"Download directory {download_dir} does not exist."}

    # Get all files in the directory
    files = [f for f in download_path.iterdir() if f.is_file()]
    if not files:
        return {"success": False, "error": f"No files found in {download_dir}."}

    # Sort by modification time (most recent first)
    files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    latest_file = files[0]

    # Destination directory
    dest_dir = Path(f"project-{project_id}/assets/current")
    dest_dir.mkdir(parents=True, exist_ok=True)

    dest_file = dest_dir / f"{record_id}.mp4"

    # Backup if exists
    if dest_file.exists():
        timestamp = int(time.time())
        backup_file = dest_dir / f"{record_id}_{timestamp}.mp4"
        shutil.move(str(dest_file), str(backup_file))
        backup_info = f"Existing file backed up to {backup_file.name}"
    else:
        backup_info = None

    # Move and rename
    shutil.move(str(latest_file), str(dest_file))

    return {
        "success": True,
        "id": record_id,
        "path": str(dest_file),
        "source": str(latest_file),
        "backup": backup_info
    }

def list_downloaded(project_id):
    """
    Lists all downloaded .mp4 files in project assets.
    """
    assets_dirs = [
        Path(f"project-{project_id}/assets"),
        Path(f"project-{project_id}/assets/current")
    ]
    
    results = []
    for d in assets_dirs:
        if d.exists() and d.is_dir():
            for f in d.iterdir():
                if f.is_file() and f.suffix == ".mp4":
                    # Check if it's a numeric ID (ignoring timestamp backups)
                    stem = f.stem
                    if stem.isdigit():
                        results.append({
                            "id": stem,
                            "filename": f.name,
                            "path": str(f),
                            "size_bytes": f.stat().st_size
                        })
    
    return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Grok Video Downloader Utility")
    parser.add_argument("--project", required=True, help="Project ID (1 or 2)")
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    # process_download command
    proc_parser = subparsers.add_parser("process_download", help="Process a downloaded file")
    proc_parser.add_argument("download_dir", help="Directory where the file was downloaded")
    proc_parser.add_argument("record_id", help="ID of the record to rename the file to")
    
    # list_downloaded command
    list_parser = subparsers.add_parser("list_downloaded", help="List all downloaded files for the project")
    
    args = parser.parse_args()
    
    if args.command == "process_download":
        result = process_download(args.project, args.download_dir, args.record_id)
        print(json.dumps(result, indent=2))
    elif args.command == "list_downloaded":
        result = list_downloaded(args.project)
        print(json.dumps(result, indent=2))
    else:
        parser.print_help()
