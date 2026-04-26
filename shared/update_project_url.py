"""
update_project_url.py
Updates the post_url for all pending prompts in grok_prompts_{N}.json.

Usage:
    python3 shared/update_project_url.py --project <1|2> --url <new_url>
"""
import json
import sys
import os
import argparse

def main():
    parser = argparse.ArgumentParser(description="Update post_url for pending prompts in a project.")
    parser.add_argument("--project", required=True, choices=["1", "2"],
                        help="Project number (1 or 2)")
    parser.add_argument("--url", required=True,
                        help="New starting Grok post URL to assign to all pending prompts")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    file_path = os.path.join(repo_root, f"grok_prompts_{args.project}.json")

    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        sys.exit(1)

    with open(file_path, "r") as f:
        data = json.load(f)

    count = 0
    for item in data["prompts"]:
        if item["status"] == "pending":
            item["post_url"] = args.url
            count += 1

    with open(file_path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"Updated {count} pending prompts in {file_path}")

if __name__ == "__main__":
    main()
