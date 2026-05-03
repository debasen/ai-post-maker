import os
import json
import argparse
import glob

def migrate_prompts(dry_run=False):
    # Find all grok_prompts.json files in project-* directories
    project_files = glob.glob("project-*/grok_prompts.json")
    
    if not project_files:
        print("No grok_prompts.json files found in project-* directories.")
        return

    for file_path in project_files:
        print(f"Processing {file_path}...")
        
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            print(f"Error reading {file_path}: {e}")
            continue

        # The JSON structure contains a 'prompts' key which holds the list of entries
        prompts = data.get("prompts", [])
        if not prompts:
            print(f"  No prompts found in {file_path}")
            continue

        modified = False
        for entry in prompts:
            if "instagram_upload" in entry:
                val = entry["instagram_upload"]
                
                # Default asset and upload values
                asset_status = "not-found"
                upload_list = entry.get("upload", [])
                
                if val == "mapped":
                    asset_status = "mapped"
                elif val == "done":
                    asset_status = "mapped"
                    # Safe default because historically both workflows shared the same done state
                    if "instagram" not in upload_list:
                        upload_list.append("instagram")
                    if "facebook" not in upload_list:
                        upload_list.append("facebook")
                elif val == "not-found":
                    asset_status = "not-found"
                
                entry["asset"] = asset_status
                entry["upload"] = upload_list
                del entry["instagram_upload"]
                modified = True
                
                if dry_run:
                    print(f"  [DRY-RUN] ID {entry.get('id')}: instagram_upload='{val}' -> asset='{asset_status}', upload={upload_list}")

        if modified:
            if not dry_run:
                with open(file_path, 'w') as f:
                    json.dump(data, f, indent=2)
                print(f"  Successfully updated {file_path}")
            else:
                print(f"  [DRY-RUN] Would have updated {file_path}")
        else:
            print(f"  No changes needed for {file_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Migrate instagram_upload field to asset and upload fields.")
    parser.add_argument("--dry-run", action="store_true", help="Perform a dry run without modifying files.")
    args = parser.parse_args()

    migrate_prompts(dry_run=args.dry_run)
