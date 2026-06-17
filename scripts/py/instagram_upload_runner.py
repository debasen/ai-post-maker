#!/usr/bin/env python3
"""
instagram_upload_runner.py — Scripted Instagram video upload (no AI required).

Converts the instagram_upload workflow into a fully scripted Python runner
using browseros-cli for browser control.

Usage:
    python3 scripts/py/instagram_upload_runner.py --project <1|2>

Steps executed per invocation:
  1. Find the first entry with instagram_upload == "mapped" in project-<N>/grok_prompts.json
  2. Open a fresh Instagram tab (new_page)
  3. Open the Create → Post modal
  4. Expose file inputs
  5. Upload the .mp4 file to the "Choose Files" input
  6. Advance through Crop → Filter/Edit → Caption screens
  7. Enter the caption
  8. Click Share
  9. Mark the entry as "done" in grok_prompts.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from typing import Optional

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
JS_DIR = os.path.join(REPO_ROOT, "scripts", "js")

INSTAGRAM_UPLOAD_JS = os.path.join(JS_DIR, "instagram_upload.min.js")

INSTAGRAM_URL = "https://www.instagram.com/"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

def log(msg: str):
    print(f"[instagram_upload] {msg}", flush=True)


def die(msg: str, code: int = 1):
    print(f"[instagram_upload] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


# ---------------------------------------------------------------------------
# browseros-cli helpers
# ---------------------------------------------------------------------------

def browseros(args):
    """Run a browseros-cli command and return stdout."""
    cmd = ["browseros-cli"] + list(args)
    log(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(f"browseros-cli failed:\n{result.stderr}")
    return result.stdout.strip()


def browseros_eval(js_code: str):
    """
    Execute JavaScript in the active browser page via browseros-cli eval.
    Returns parsed JSON result.
    """
    cmd = ["browseros-cli", "eval", js_code, "--json"]
    log("$ browseros-cli eval <script> --json")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        die(f"browseros-cli eval failed:\n{result.stderr}")

    raw = result.stdout.strip()
    try:
        envelope = json.loads(raw)
        if isinstance(envelope, dict):
            if "value" in envelope:
                inner = envelope["value"]
            elif "result" in envelope:
                inner = envelope["result"]
            else:
                inner = envelope

            if isinstance(inner, str):
                try:
                    return json.loads(inner)
                except json.JSONDecodeError:
                    pass
            return inner
        return envelope
    except json.JSONDecodeError:
        die(f"Unexpected eval output:\n{raw}")


def load_js(path: str) -> str:
    with open(path, "r") as f:
        return f.read()


def build_eval(fn_call: str) -> str:
    """Prepend the instagram_upload library, then wrap fn_call in an IIFE."""
    lib_js = load_js(INSTAGRAM_UPLOAD_JS)
    return (
        "(async () => {\n"
        f"  {lib_js}\n"
        f"  return await {fn_call};\n"
        "})();"
    )


# ---------------------------------------------------------------------------
# browseros snapshot helpers
# ---------------------------------------------------------------------------

def get_snapshot_raw() -> str:
    """Return the raw snapshot string."""
    raw = browseros(["snap", "--json"])
    try:
        envelope = json.loads(raw)
        return envelope.get("snapshot", raw)
    except Exception:
        return raw


def find_element_id_in_snapshot(snapshot_str: str, label_keywords: list) -> Optional[str]:
    """
    Walk snapshot lines looking for a line that contains ALL label_keywords
    (case-insensitive) and extract the bracketed element ID, e.g. [1234].
    """
    for line in snapshot_str.split("\n"):
        lower = line.lower()
        if all(kw.lower() in lower for kw in label_keywords):
            match = re.search(r'\[(\d+)\]', line)
            if match:
                return match.group(1)
    return None


# ---------------------------------------------------------------------------
# grok_prompts.json helpers
# ---------------------------------------------------------------------------

def get_prompts_path(project: str) -> str:
    return os.path.join(REPO_ROOT, f"project-{project}", "grok_prompts.json")


def find_mapped_entry(project: str):
    """
    Return the first entry with instagram_upload == 'mapped'.
    Returns (entry_dict, file_path) or dies if none found.
    """
    filepath = get_prompts_path(project)
    if not os.path.exists(filepath):
        die(f"File not found: {filepath}")

    with open(filepath, "r") as f:
        data = json.load(f)

    for entry in data.get("prompts", []):
        if entry.get("instagram_upload") == "mapped":
            return entry, filepath

    log("No entries with instagram_upload == 'mapped' found. Nothing to do.")
    sys.exit(0)


def mark_entry_done(filepath: str, entry_id: int):
    """Update the entry's instagram_upload field to 'done'."""
    with open(filepath, "r") as f:
        data = json.load(f)

    updated = False
    for entry in data.get("prompts", []):
        if entry.get("id") == entry_id:
            entry["instagram_upload"] = "done"
            updated = True
            break

    if not updated:
        die(f"ID {entry_id} not found in {filepath} when trying to mark done.")

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)

    log(f"Marked entry ID {entry_id} as done in {filepath}")


# ---------------------------------------------------------------------------
# Core upload steps
# ---------------------------------------------------------------------------

def step_open_new_page() -> str:
    """Open a fresh Instagram tab. Returns the page ID."""
    log(f"Opening fresh Instagram tab at {INSTAGRAM_URL}...")
    raw = browseros(["open", INSTAGRAM_URL, "--json"])
    try:
        result = json.loads(raw)
        page_id = result.get("pageId") or result.get("id") or result.get("tabId") or ""
        if page_id:
            log(f"New page opened. Page ID: {page_id}")
        else:
            log("New page opened (could not parse page ID from response).")
        return str(page_id)
    except Exception:
        log("New page opened (non-JSON response).")
        return ""


def step_wait_for_page_load(seconds: int = 4):
    log(f"Waiting {seconds}s for Instagram to load...")
    time.sleep(seconds)


def step_open_create_modal():
    """Step 3: Click Create → Post to open the upload modal."""
    log("Step 3: Opening Create → Post modal...")
    result = browseros_eval(build_eval("openCreateModal()"))
    log(f"openCreateModal result: {result}")
    if not (isinstance(result, dict) and result.get("success")):
        die(f"Failed to open create modal: {result}")


def step_expose_file_inputs():
    """Step 4: Expose hidden file inputs so upload_file can target them."""
    log("Step 4: Exposing file inputs...")
    result = browseros_eval(build_eval("exposeFileInputs()"))
    log(f"exposeFileInputs result: {result}")
    return result


def find_choose_files_element() -> str:
    """
    Take a snapshot and find the 'Choose Files' file input element ID.
    Returns the element ID string.
    """
    log("Taking snapshot to locate 'Choose Files' element...")
    snapshot_str = get_snapshot_raw()

    # Try 'Choose Files' first
    el_id = find_element_id_in_snapshot(snapshot_str, ["choose files"])
    if el_id:
        log(f"Found 'Choose Files' element ID: {el_id}")
        return el_id

    # Fallback: look for ig_file_input_1 (the second file input we exposed)
    el_id = find_element_id_in_snapshot(snapshot_str, ["ig_file_input_1"])
    if el_id:
        log(f"Found ig_file_input_1 element ID: {el_id}")
        return el_id

    # Fallback: any file input element
    el_id = find_element_id_in_snapshot(snapshot_str, ["file"])
    if el_id:
        log(f"Found file input element ID (fallback): {el_id}")
        return el_id

    die("Could not find 'Choose Files' file input in snapshot.")


def step_upload_file(element_id: str, asset_path: str):
    """Step 5: Upload the .mp4 file to the exposed file input."""
    log(f"Step 5: Uploading file '{asset_path}' to element [{element_id}]...")
    if not os.path.exists(asset_path):
        die(f"Asset file not found: {asset_path}")
    browseros(["upload", element_id, asset_path])
    log("File upload triggered. Waiting for React to process it...")
    time.sleep(2)


def step_advance_to_caption():
    """Step 6: Navigate Crop → Filter/Edit → Caption screens."""
    log("Step 6: Advancing through Crop → Filter/Edit → Caption screens...")
    result = browseros_eval(build_eval("advanceToCaption()"))
    log(f"advanceToCaption result: {result}")
    if not (isinstance(result, dict) and result.get("success")):
        die(f"Failed to advance to caption screen: {result}")
    modal = result.get("modalLabelAfter", "")
    log(f"Modal after navigation: '{modal}'")


def step_enter_caption(caption_text: str):
    """Step 7: Enter the caption text."""
    log(f"Step 7: Entering caption ({len(caption_text)} chars)...")
    caption_json = json.dumps(caption_text)
    result = browseros_eval(build_eval(f"enterCaption({caption_json})"))
    log(f"enterCaption result: {result}")
    if not (isinstance(result, dict) and result.get("success")):
        die(f"Failed to enter caption: {result}")
    if not result.get("shareBtnFound"):
        log("WARNING: Share button not found after entering caption. Proceeding anyway.")


def step_click_share():
    """Step 8: Click the Share button."""
    log("Step 8: Clicking Share...")
    result = browseros_eval(build_eval("clickShare()"))
    log(f"clickShare result: {result}")
    if not (isinstance(result, dict) and result.get("success")):
        die(f"Failed to click Share: {result}")
    log("Share clicked! Waiting for post to submit...")
    time.sleep(5)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Instagram upload runner (no AI required). "
            "Uploads exactly one mapped asset per invocation."
        )
    )
    parser.add_argument(
        "--project", required=True,
        choices=["1", "2", "3", "4"],
        help="Project number (1, 2, 3, or 4)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Run all steps except actually clicking Share and marking done"
    )
    args = parser.parse_args()
    project = args.project

    # ------------------------------------------------------------------
    # Step 1: Find mapped entry
    # ------------------------------------------------------------------
    log("Step 1: Finding mapped entry in grok_prompts.json...")
    entry, prompts_path = find_mapped_entry(project)

    entry_id = entry["id"]
    caption = entry.get("instagram_caption", "")
    asset_path = os.path.join(REPO_ROOT, f"project-{project}", "assets", f"{entry_id}.mp4")

    log(f"Entry ID: {entry_id}")
    log(f"Asset:    {asset_path}")
    log(f"Caption:  {caption[:80]}{'...' if len(caption) > 80 else ''}")

    if not os.path.exists(asset_path):
        die(f"Asset file not found: {asset_path}")

    # ------------------------------------------------------------------
    # Step 2: Open fresh Instagram tab
    # ------------------------------------------------------------------
    log("Step 2: Opening fresh Instagram tab...")
    step_open_new_page()
    step_wait_for_page_load(5)

    # ------------------------------------------------------------------
    # Step 3: Open Create → Post modal
    # ------------------------------------------------------------------
    step_open_create_modal()

    # ------------------------------------------------------------------
    # Step 4: Expose file inputs
    # ------------------------------------------------------------------
    step_expose_file_inputs()

    # ------------------------------------------------------------------
    # Step 4b: Find the "Choose Files" element ID from snapshot
    # ------------------------------------------------------------------
    choose_files_id = find_choose_files_element()

    # ------------------------------------------------------------------
    # Step 5: Upload file
    # ------------------------------------------------------------------
    step_upload_file(choose_files_id, asset_path)

    # ------------------------------------------------------------------
    # Step 6: Advance to caption screen
    # ------------------------------------------------------------------
    step_advance_to_caption()

    # ------------------------------------------------------------------
    # Step 7: Enter caption
    # ------------------------------------------------------------------
    step_enter_caption(caption)

    # ------------------------------------------------------------------
    # Step 8: Click Share (unless --dry-run)
    # ------------------------------------------------------------------
    if args.dry_run:
        log("DRY-RUN: Skipping Share click and JSON update.")
        log(f"Would have shared entry ID {entry_id} for project {project}.")
        sys.exit(0)

    step_click_share()

    # ------------------------------------------------------------------
    # Step 9: Mark entry as done
    # ------------------------------------------------------------------
    log("Step 9: Marking entry as done in grok_prompts.json...")
    mark_entry_done(prompts_path, entry_id)

    log(f"Done! Entry {entry_id} for project {project} uploaded to Instagram successfully.")


if __name__ == "__main__":
    main()
