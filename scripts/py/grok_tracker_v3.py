import json
import os
import sys
from datetime import datetime

def get_project_path(project_id):
    """Resolve the path to grok_prompts.json in the project folder."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(os.path.dirname(script_dir))
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
    """Print the config section."""
    data = load_data(file_path)
    config = data.get("config", {})
    print(json.dumps(config))

def get_next(file_path):
    """Print the first pending prompt."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    for item in prompts:
        if item.get("status") == "pending":
            print(json.dumps(item))
            return
    print(json.dumps({"error": "No pending prompts"}))

def update_field(file_path, prompt_id, field_name, value):
    """Update a specific field for a prompt."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item[field_name] = value
            found = True
            break
    
    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "field": field_name}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

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
            # Clean up old warning/failure timestamps
            for key in ["video_warning_at", "image_warning_at", "extend_warning_at",
                        "video_failed_at", "image_failed_at", "extend_failed_at", "failed_at", "partial_at"]:
                item.pop(key, None)
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_partial(file_path, prompt_id, video_url, post_url):
    """Mark a prompt as partial — video succeeded but extend failed."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "partial"
            item["video_url"] = video_url
            item["post_url"] = post_url
            item["partial_at"] = datetime.now().isoformat()
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": "partial"}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_failed(file_path, prompt_id, post_url):
    """Mark a prompt as failed — image generation failed (terminal)."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "failed"
            item["post_url"] = post_url
            item["failed_at"] = datetime.now().isoformat()
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": "failed"}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_video_failed(file_path, prompt_id, post_url):
    """Mark a prompt as video_failed — terminal."""
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

def mark_extend_failed(file_path, prompt_id, post_url):
    """Mark a prompt as extend_failed — terminal (but video may exist)."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "extend_failed"
            item["post_url"] = post_url
            item["extend_failed_at"] = datetime.now().isoformat()
            found = True
            break

    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "status": "extend_failed"}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def get_next_to_map(file_path):
    """Print the first prompt missing asset status."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    for item in prompts:
        if item.get("status") == "completed" and "asset" not in item:
            print(json.dumps(item))
            return
    print(json.dumps({"error": "No prompts to map"}))

def update_mapping_status(file_path, prompt_id, status):
    """Update asset field."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            item["asset"] = status
            found = True
            break
    
    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "asset": status}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def mark_uploaded(file_path, prompt_id, platform):
    """Append platform to upload array."""
    data = load_data(file_path)
    prompts = data.get("prompts", [])
    found = False
    for item in prompts:
        if str(item.get("id")) == str(prompt_id):
            if "upload" not in item:
                item["upload"] = []
            if platform not in item["upload"]:
                item["upload"].append(platform)
            found = True
            break
    
    if found:
        save_data(file_path, data)
        print(json.dumps({"success": True, "id": prompt_id, "platform": platform}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

def print_usage():
    print(
        "Usage: python3 scripts/py/grok_tracker_v3.py --project <1|2|3> "
        "[get_next | get_config | complete <id> <video_url> <post_url> | "
        "mark_partial <id> <video_url> <post_url> | "
        "mark_failed <id> <post_url> | "
        "mark_video_failed <id> <post_url> | "
        "mark_extend_failed <id> <post_url> | "
        "update_field <id> <field_name> <value> | "
        "get_next_to_map | update_mapping_status <id> <status> | "
        "mark_uploaded <id> <platform>]"
    )

if __name__ == "__main__":
    args = sys.argv[1:]

    if len(args) < 3 or args[0] != "--project":
        print_usage()
        sys.exit(1)

    project_id = args[1]
    if project_id not in ("1", "2", "3"):
        print(json.dumps({"error": f"Invalid project '{project_id}'. Must be 1, 2, or 3."}))
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
    elif command == "mark_partial":
        if len(args) < 6:
            print("Usage: ... mark_partial <id> <video_url> <post_url>")
            sys.exit(1)
        mark_partial(file_path, args[3], args[4], args[5])
    elif command == "mark_failed":
        if len(args) < 5:
            print("Usage: ... mark_failed <id> <post_url>")
            sys.exit(1)
        mark_failed(file_path, args[3], args[4])
    elif command == "mark_video_failed":
        if len(args) < 5:
            print("Usage: ... mark_video_failed <id> <post_url>")
            sys.exit(1)
        mark_video_failed(file_path, args[3], args[4])
    elif command == "mark_extend_failed":
        if len(args) < 5:
            print("Usage: ... mark_extend_failed <id> <post_url>")
            sys.exit(1)
        mark_extend_failed(file_path, args[3], args[4])
    elif command == "update_field":
        if len(args) < 6:
            print("Usage: ... update_field <id> <field_name> <value>")
            sys.exit(1)
        update_field(file_path, args[3], args[4], args[5])
    elif command == "mark_uploaded":
        if len(args) < 5:
            print("Usage: ... mark_uploaded <id> <platform>")
            sys.exit(1)
        mark_uploaded(file_path, args[3], args[4])
    else:
        print(json.dumps({"error": f"Unknown command '{command}'"}))
        print_usage()
        sys.exit(1)
