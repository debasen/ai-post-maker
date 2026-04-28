import json
import os
import sys
from datetime import datetime

def get_project_path(project_id):
    """Resolve the path to grok_prompts.json in the project folder."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    return os.path.join(repo_root, f"project-{project_id}", "grok_prompts.json")

def load_data(file_path):
    if not os.path.exists(file_path):
        print(json.dumps({"error": f"File not found: {file_path}"}))
        sys.exit(1)
    with open(file_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            print(json.dumps({"error": f"JSON parse error: {str(e)}"}))
            sys.exit(1)

def save_data(file_path, data):
    with open(file_path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def get_config(file_path):
    """Print the config section (thumbnail_id and derived starting_url)."""
    data = load_data(file_path)
    config = data.get("config", {})
    if "thumbnail_id" in config and "starting_url" not in config:
        config["starting_url"] = f"https://grok.com/imagine/post/{config['thumbnail_id']}"
    print(json.dumps(config))

def get_next(file_path):
    """Print the first video_failed (retry) or pending prompt."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    # Priority 1: video_failed (retry candidates)
    for item in prompts:
        if item.get("status") == "video_failed":
            result = dict(item)
            result["retry_mode"] = True
            print(json.dumps(result))
            return
    # Priority 2: pending (new items)
    for item in prompts:
        if item.get("status") == "pending":
            result = dict(item)
            result["retry_mode"] = False
            print(json.dumps(result))
            return
    print(json.dumps({"error": "No pending or retry prompts"}))

def complete(file_path, prompt_id, video_url, post_url):
    """Mark a prompt as completed with its URLs."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "completed"
            item["video_url"] = video_url
            item["post_url"] = post_url
            item["executed_at"] = datetime.now().isoformat()
            # Clean up any failure timestamps if reprocessed
            item.pop("video_failed_at", None)
            item.pop("failed_at", None)
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_video_failed(file_path, prompt_id, post_url):
    """Mark a prompt as video_failed after first failure."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "video_failed"
            item["post_url"] = post_url
            item["video_failed_at"] = datetime.now().isoformat()
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": "video_failed"}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_failed(file_path, prompt_id):
    """Mark a prompt as failed (terminal, no more retries)."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "failed"
            item["failed_at"] = datetime.now().isoformat()
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": "failed"}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def get_next_to_map(file_path):
    """Print the first prompt missing instagram_upload."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    for item in prompts:
        # We only map completed prompts that haven't been mapped yet
        if item.get("status") == "completed" and "instagram_upload" not in item:
            print(json.dumps(item))
            return
    print(json.dumps({"error": "No prompts to map"}))

def update_mapping_status(file_path, prompt_id, status):
    """Update instagram_upload field (done, not-found)."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["instagram_upload"] = status
            found = True
            break
    
    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": status}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def print_usage():
    print(
        "Usage: python3 shared/grok_tracker.py --project <1|2> "
        "[get_next | get_config | complete <id> <video_url> <post_url> | "
        "mark_video_failed <id> <post_url> | mark_failed <id> | "
        "get_next_to_map | update_mapping_status <id> <status>]"
    )

if __name__ == "__main__":
    args = sys.argv[1:]

    # Parse --project flag
    if len(args) < 3 or args[0] != "--project":
        print_usage()
        sys.exit(1)

    project_id = args[1]
    if project_id not in ("1", "2"):
        print(json.dumps({"error": f"Invalid project '{project_id}'. Must be 1 or 2."}))
        sys.exit(1)

    file_path = get_project_path(project_id)
    command = args[2]

    if command == "get_next":
        get_next(file_path)
    elif command == "get_next_to_map":
        get_next_to_map(file_path)
    elif command == "update_mapping_status":
        if len(args) < 5:
            print("Usage: ... update_mapping_status <id> <status>")
            sys.exit(1)
        update_mapping_status(file_path, args[3], args[4])
    elif command == "get_config":
        get_config(file_path)
    elif command == "complete":
        if len(args) < 6:
            print("Usage: ... complete <id> <video_url> <post_url>")
            sys.exit(1)
        complete(file_path, args[3], args[4], args[5])
    elif command == "mark_video_failed":
        if len(args) < 5:
            print("Usage: ... mark_video_failed <id> <post_url>")
            sys.exit(1)
        mark_video_failed(file_path, args[3], args[4])
    elif command == "mark_failed":
        if len(args) < 4:
            print("Usage: ... mark_failed <id>")
            sys.exit(1)
        mark_failed(file_path, args[3])
    else:
        print(json.dumps({"error": f"Unknown command '{command}'"}))
        print_usage()
        sys.exit(1)
