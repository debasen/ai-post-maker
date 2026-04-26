import json
import os
import sys
from datetime import datetime

# Adjust path if script is run from project root
FILE_PATH = "grok_prompts.json"

def load_data():
    if not os.path.exists(FILE_PATH):
        return []
    with open(FILE_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            return []

def save_data(data):
    with open(FILE_PATH, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def get_next():
    data = load_data()
    for item in data:
        if item.get("status") == "pending":
            print(json.dumps(item))
            return
    print(json.dumps({"error": "No pending prompts"}))

def complete(prompt_id, video_url, post_url):
    data = load_data()
    found = False
    for item in data:
        if str(item.get("id")) == str(prompt_id):
            item["status"] = "completed"
            item["video_url"] = video_url
            item["post_url"] = post_url
            item["executed_at"] = datetime.now().isoformat()
            found = True
            break
    
    if found:
        save_data(data)
        print(json.dumps({"success": True, "id": prompt_id}))
    else:
        print(json.dumps({"success": False, "error": f"ID {prompt_id} not found"}))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python grok_tracker.py [get_next | complete <id> <video_url> <post_url>]")
        sys.exit(1)
    
    command = sys.argv[1]
    if command == "get_next":
        get_next()
    elif command == "complete":
        if len(sys.argv) < 5:
            print("Usage: python grok_tracker.py complete <id> <video_url> <post_url>")
            sys.exit(1)
        complete(sys.argv[2], sys.argv[3], sys.argv[4])
