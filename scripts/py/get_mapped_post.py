#!/usr/bin/env python3
"""
get_mapped_post.py — Extract the first prompt with 'mapped' status from grok_prompts.json.

Usage:
  python3 scripts/py/get_mapped_post.py --project <1|2|...>
"""

import argparse
import json
import re
import sys
from pathlib import Path

def get_project_path(project_id: int) -> Path:
    """Resolve the path to grok_prompts.json in the project folder."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    return repo_root / f"project-{project_id}" / "grok_prompts.json"

def get_caption_from_md(project_id: int, prompt_id: int) -> str:
    """Fall back to reading from recipes.md if caption is missing in JSON."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    md_path = repo_root / f"project-{project_id}" / "recipes.md"
    
    if not md_path.exists():
        return ""
        
    with open(md_path, "r") as f:
        content = f.read()
    
    # Matches: ID: <id>\nCaption:\n```\n<caption_content>\n```
    pattern = rf"ID:\s*{prompt_id}\s*\nCaption:\s*\n```\s*\n(.*?)\n```"
    match = re.search(pattern, content, re.DOTALL)
    if match:
        return match.group(1).strip()
    return ""

def main():
    parser = argparse.ArgumentParser(
        description="Extract the first prompt with 'mapped' status from grok_prompts.json"
    )
    parser.add_argument("--project", type=int, required=True, help="Project ID")
    parser.add_argument("--platform", type=str, required=True, choices=["instagram", "facebook", "youtube"], help="Platform to check")
    args = parser.parse_args()

    filepath = get_project_path(args.project)
    if not filepath.exists():
        print(f"❌ File not found: {filepath}")
        sys.exit(1)

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"❌ Failed to decode JSON: {filepath} - {e}")
            sys.exit(1)

    # The JSON structure contains a 'prompts' key which holds the list of entries
    prompts = data.get("prompts", [])
    for entry in prompts:
        if entry.get("asset") == "mapped" and args.platform not in entry.get("upload", []):
            prompt_id = entry["id"]
            caption = entry.get("instagram_caption")
            
            # Fallback to recipes.md if caption is missing or empty
            if not caption:
                caption = get_caption_from_md(args.project, prompt_id)
            
            print(f"ID: {prompt_id}")
            print(f"Caption: {caption}")
            return

    print(f"⚠️  No prompts with 'mapped' status found in project-{args.project} for platform {args.platform}")
    sys.exit(0)

if __name__ == "__main__":
    main()
