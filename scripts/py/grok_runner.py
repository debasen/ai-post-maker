#!/usr/bin/env python3
"""
grok_runner.py — Hardcoded Grok automation script (no AI required).

Converts the grok_automation workflow into a fully scripted Python runner
using browseros-cli for browser control.

Usage:
    python3 scripts/py/grok_runner.py --project <1|2>

Steps executed per invocation:
  1. Get next record from tracker
  2. Read project config (starting_url, thumbnail_id)
  3A. Full flow (pending / image_warning): navigate → run automateGrokGeneration → check result
  3B. Video-only flow (video_warning): navigate to post_url → run video-only generation
  4. Sleep 90s
  5. Poll for completion
  6. Update tracker (success or failure — warnings are treated as terminal)
  7. Download final video
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
JS_DIR = os.path.join(REPO_ROOT, "scripts", "js")

GROK_AUTOMATION_JS = os.path.join(JS_DIR, "grok_automation.min.js")
GROK_CHECK_JS = os.path.join(JS_DIR, "grok_check.min.js")

TRACKER = os.path.join(SCRIPT_DIR, "grok_tracker.py")
DOWNLOADER = os.path.join(SCRIPT_DIR, "grok_video_downloader.py")

SLEEP_BEFORE_CHECK = 90  # seconds (Step 4)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str):
    print(f"[grok_runner] {msg}", flush=True)


def die(msg: str, code: int = 1):
    print(f"[grok_runner] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def run_python(args):
    """Run a python3 subprocess and return parsed JSON stdout."""
    cmd = ["python3"] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(f"Command failed: {' '.join(cmd)}\n{result.stderr}")
    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        die(f"Non-JSON output from: {' '.join(cmd)}\n{result.stdout}")


def run_browseros_cli(cmd, log_cmd=True):
    """Run a browseros-cli command with auto-reconnect on connection errors."""
    if log_cmd:
        log(f"$ {' '.join(str(a) for a in cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        err_msg = result.stderr.lower()
        connection_errors = ["connection refused", "cannot connect", "no active page", "session with given id", "cdp error", "dial tcp"]
        if any(x in err_msg for x in connection_errors):
            log("Connection error detected. Attempting to reconnect via browseros-cli init --auto...")
            recon = subprocess.run(["browseros-cli", "init", "--auto"], capture_output=True, text=True)
            if recon.returncode == 0:
                log("Reconnected successfully. Retrying command...")
                time.sleep(2)
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                # If session is invalid after reconnection, the saved active page might be closed.
                if result.returncode != 0 and "session with given id" in result.stderr.lower():
                    log("Session ID is invalid. Opening a new page to recover...")
                    subprocess.run(["browseros-cli", "open", "about:blank"], capture_output=True)
                    time.sleep(2)
                    log("Retrying command again on new page...")
                    result = subprocess.run(cmd, capture_output=True, text=True)
            else:
                log(f"Reconnection attempt failed:\n{recon.stderr}")
    return result


def browseros(args):
    """Run a browseros-cli command and return stdout."""
    cmd = ["browseros-cli"] + list(args)
    result = run_browseros_cli(cmd)
    if result.returncode != 0:
        die(f"browseros-cli failed:\n{result.stderr}")
    return result.stdout.strip()


def browseros_eval(js_code: str):
    """
    Execute JavaScript in the active browser page via browseros-cli eval.
    Passes the JS as a positional string argument.
    Returns parsed JSON result.
    """
    # browseros-cli eval takes the expression as a positional string arg.
    # We use --json to get machine-readable output.
    # We increase the timeout to 5m to prevent timeouts during image/video generation steps.
    cmd = ["browseros-cli", "eval", js_code, "--json", "--timeout", "5m"]
    result = run_browseros_cli(cmd)

    if result.returncode != 0:
        die(f"browseros-cli eval failed:\n{result.stderr}")

    raw = result.stdout.strip()
    try:
        envelope = json.loads(raw)
        if isinstance(envelope, dict):
            # browseros-cli --json wraps output in {value: ...} or {result: ...}
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


# ---------------------------------------------------------------------------
# Tracker helpers
# ---------------------------------------------------------------------------

def tracker(project: str, *args):
    return run_python([TRACKER, "--project", project] + list(args))


def get_next(project: str):
    return tracker(project, "get_next")


def get_config(project: str):
    return tracker(project, "get_config")


def mark_image_failed(project: str, record_id, post_url: str):
    tracker(project, "mark_image_failed", str(record_id), post_url)
    log(f"Marked record {record_id} as image_failed.")


def mark_video_failed(project: str, record_id, post_url: str):
    tracker(project, "mark_video_failed", str(record_id), post_url)
    log(f"Marked record {record_id} as video_failed.")


def mark_complete(project: str, record_id, video_url: str, post_url: str):
    tracker(project, "complete", str(record_id), video_url, post_url)
    log(f"Marked record {record_id} as completed.")


# ---------------------------------------------------------------------------
# JS script builders
# ---------------------------------------------------------------------------

def build_full_flow_script(record: dict) -> str:
    """Build the eval JS for Step 3A (full flow)."""
    automation_js = load_js(GROK_AUTOMATION_JS)

    prompt_text = record.get("prompt", "")
    video_prompt = record.get("video_prompt")   # None or string
    video_type = record.get("video_type")       # None or "spicy" etc.

    prompt_json = json.dumps(prompt_text)
    video_prompt_json = json.dumps(video_prompt)
    video_type_json = json.dumps(video_type)

    return (
        "(async () => {\n"
        f"  {automation_js}\n"
        "  return await automateGrokGeneration({\n"
        f"    promptText: {prompt_json},\n"
        "    thumbnailId: null,\n"
        f"    videoPromptText: {video_prompt_json},\n"
        f"    videoType: {video_type_json},\n"
        "    skipImageGeneration: false\n"
        "  });\n"
        "})();"
    )


def build_video_only_script(record: dict) -> str:
    """Build the eval JS for Step 3B (video-only flow)."""
    automation_js = load_js(GROK_AUTOMATION_JS)
    post_url = record.get("post_url", "")
    post_url_json = json.dumps(post_url)

    return (
        "(async () => {\n"
        f"  {automation_js}\n"
        "  return await automateGrokGeneration({\n"
        "    skipImageGeneration: true,\n"
        f"    postUrl: {post_url_json}\n"
        "  });\n"
        "})();"
    )


def build_check_script() -> str:
    """Build the eval JS for Step 5 (check completion)."""
    check_js = load_js(GROK_CHECK_JS)
    return (
        "(async () => {\n"
        f"  {check_js}\n"
        "  return await checkVideoCompletion();\n"
        "})();"
    )


# ---------------------------------------------------------------------------
# Core steps
# ---------------------------------------------------------------------------

def step_navigate(url: str):
    """Navigate the active browser page to a URL."""
    log(f"Navigating to: {url}")
    browseros(["nav", url])
    time.sleep(3)  # Give the page time to load


def find_download_snapshot_id() -> str:
    """Find the snapshot ID of the Download button using browseros-cli snap."""
    log("Finding Download button snapshot ID...")
    raw = browseros(["snap", "--json"])
    try:
        envelope = json.loads(raw)
        snapshot_str = envelope.get("snapshot", "")
        # Look for the line containing button and download (case-insensitive)
        for line in snapshot_str.split("\n"):
            if "button" in line.lower() and "download" in line.lower():
                match = re.search(r'\[(\d+)\]', line)
                if match:
                    element_id = match.group(1)
                    log(f"Found Download button snapshot ID: {element_id}")
                    return element_id
    except Exception as e:
        log(f"Failed to parse snapshot JSON: {e}")
    
    die("Download button snapshot ID not found in snapshot.")


def step_download(project: str, record_id, dest_dir: str):
    """Step 7: Click Download button and rename the file."""
    # Try robust Base64 fetch method first
    log("Attempting robust Base64 video fetch...")
    js_code = """(async () => {
        const v = document.querySelector('video');
        if (!v) return { "success": false, "error": "No video element found" };
        if (!v.src) return { "success": false, "error": "Video element has no src attribute" };
        try {
            const response = await fetch(v.src);
            if (!response.ok) return { "success": false, "error": `Fetch failed with status ${response.status}` };
            const blob = await response.blob();
            return new Promise((resolve) => {
                const reader = new FileReader();
                reader.onloadend = () => resolve({ "success": true, "base64": reader.result.split(',')[1] });
                reader.onerror = (e) => resolve({ "success": false, "error": `FileReader error: ${e.target.error}` });
                reader.readAsDataURL(blob);
            });
        } catch (e) {
            return { "success": false, "error": `Fetch exception: ${e.message}` };
        }
    })()"""
    
    try:
        res = browseros_eval(js_code)
        if res and res.get("success") and res.get("base64"):
            log("Base64 fetch succeeded. Saving video...")
            dest_path = os.path.join(dest_dir, f"{record_id}.mp4")
            
            # Backup if exists
            if os.path.exists(dest_path):
                backup_path = os.path.join(dest_dir, f"{record_id}_{int(time.time())}.mp4")
                import shutil
                shutil.move(dest_path, backup_path)
                log(f"Backed up existing file to {os.path.basename(backup_path)}")
                
            import base64
            with open(dest_path, "wb") as f:
                f.write(base64.b64decode(res["base64"]))
                
            if os.path.exists(dest_path) and os.path.getsize(dest_path) > 0:
                log(f"Video saved successfully via Base64: {dest_path}")
                return dest_path
            else:
                log("Saved file was empty or missing. Falling back to browseros-cli download...")
        else:
            log(f"Base64 fetch returned failure: {res.get('error') if res else 'unknown error'}. Falling back...")
    except Exception as e:
        log(f"Base64 fetch failed with exception: {e}. Falling back to browseros-cli download...")

    # Fallback to browseros-cli download
    element_id = find_download_snapshot_id()

    log(f"Clicking Download button (snapshot ID: {element_id})...")
    # browseros-cli download takes <element_id> <dir> as positional args
    browseros(["download", element_id, dest_dir])

    log("Processing downloaded file...")
    result = run_python([
        DOWNLOADER,
        "--project", project,
        "process_download",
        dest_dir,
        str(record_id)
    ])

    if not result.get("success"):
        die(f"process_download failed: {result.get('error', 'unknown error')}")

    dest_path = result.get("path", "")
    if not os.path.exists(dest_path) or os.path.getsize(dest_path) == 0:
        die(f"Downloaded file missing or empty: {dest_path}")

    log(f"Video saved via fallback: {dest_path}")
    return dest_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Grok automation runner (no AI required). "
            "Processes one pending record per invocation."
        )
    )
    parser.add_argument(
        "--project", required=True,
        choices=["1", "2", "3", "4"],
        help="Project number (1, 2, 3, or 4)"
    )
    args = parser.parse_args()
    project = args.project

    # ------------------------------------------------------------------
    # Step 1: Get next record
    # ------------------------------------------------------------------
    log("Step 1: Getting next record...")
    record = get_next(project)

    if "error" in record:
        log(f"Nothing to do: {record['error']}")
        sys.exit(0)

    record_id = record["id"]
    starting_status = record.get("status", "pending")
    post_url = record.get("post_url") or ""

    log(f"Record {record_id} | status={starting_status}")

    # ------------------------------------------------------------------
    # Step 2: Read project config
    # ------------------------------------------------------------------
    log("Step 2: Reading project config...")
    config = get_config(project)
    starting_url = config.get("starting_url")
    if not starting_url:
        die("Config missing 'starting_url'")

    # ------------------------------------------------------------------
    # Destination directory for downloads
    # ------------------------------------------------------------------
    dest_dir = os.path.join(REPO_ROOT, f"project-{project}", "assets", "current")
    os.makedirs(dest_dir, exist_ok=True)
    dest_dir_slash = dest_dir.rstrip("/") + "/"

    # ------------------------------------------------------------------
    # Step 3: Automate generation
    # ------------------------------------------------------------------
    current_video_url = ""
    current_post_url = post_url

    if starting_status == "video_warning":
        # ----------------------------------------------------------------
        # Step 3B: Video-only flow
        # ----------------------------------------------------------------
        log("Step 3B: Video-only flow (starting status = video_warning)...")
        if not post_url:
            die("Record has video_warning status but no post_url set.")

        step_navigate(post_url)
        js = build_video_only_script(record)
        log("Evaluating video-only generation script...")
        gen_result = browseros_eval(js)
        log(f"Generation result: {gen_result}")

        gen_status = gen_result.get("status")
        current_post_url = gen_result.get("postUrl") or gen_result.get("post_url") or post_url
        current_video_url = gen_result.get("videoUrl") or gen_result.get("video_url") or ""

        if gen_status == "video_warning":
            # 6B-ii: Second video failure → terminal
            log("Video warning on 3B (second failure) — marking as video_failed.")
            mark_video_failed(project, record_id, current_post_url)
            sys.exit(0)
        elif gen_status != "ok":
            log(f"Unexpected status '{gen_status}' on 3B — treating as video_failed.")
            mark_video_failed(project, record_id, current_post_url)
            sys.exit(0)

    else:
        # ----------------------------------------------------------------
        # Step 3A: Full flow (pending / image_warning)
        # ----------------------------------------------------------------
        log(f"Step 3A: Full flow (starting status = {starting_status})...")
        step_navigate(starting_url)
        js = build_full_flow_script(record)
        log("Evaluating full generation script...")
        gen_result = browseros_eval(js)
        log(f"Generation result: {gen_result}")

        gen_status = gen_result.get("status")
        current_post_url = gen_result.get("postUrl") or gen_result.get("post_url") or post_url
        current_video_url = gen_result.get("videoUrl") or gen_result.get("video_url") or ""

        if gen_status == "image_warning":
            # Any image failure → terminal
            log("Image warning on 3A — marking as image_failed (terminal).")
            mark_image_failed(project, record_id, current_post_url)
            sys.exit(0)
        elif gen_status == "video_warning":
            # First video failure from 3A → terminal
            log("Video warning on 3A — marking as video_failed (terminal).")
            mark_video_failed(project, record_id, current_post_url)
            sys.exit(0)
        elif gen_status != "ok":
            log(f"Unexpected status '{gen_status}' on 3A — treating as image_failed.")
            mark_image_failed(project, record_id, current_post_url)
            sys.exit(0)

    # ------------------------------------------------------------------
    # Step 4: Sleep before checking completion
    # ------------------------------------------------------------------
    log(f"Step 4: Sleeping {SLEEP_BEFORE_CHECK}s to allow generation to progress...")
    time.sleep(SLEEP_BEFORE_CHECK)

    # ------------------------------------------------------------------
    # Step 5: Check completion
    # ------------------------------------------------------------------
    log("Step 5: Checking video completion...")
    check_js = build_check_script()
    check_result = browseros_eval(check_js)
    log(f"Check result: {check_result}")

    check_status = check_result.get("status")
    final_video_url = check_result.get("videoUrl") or current_video_url
    final_post_url = current_post_url

    if check_status == "video_warning":
        log("Video warning at completion check — marking as video_failed.")
        mark_video_failed(project, record_id, final_post_url)
        sys.exit(0)
    elif check_status != "completed":
        log(f"Unexpected check status '{check_status}' — marking as video_failed.")
        mark_video_failed(project, record_id, final_post_url)
        sys.exit(0)

    # ------------------------------------------------------------------
    # Step 6C: Success — update tracker
    # ------------------------------------------------------------------
    log("Step 6C: Success! Marking record as completed...")
    mark_complete(project, record_id, final_video_url, final_post_url)

    # ------------------------------------------------------------------
    # Step 7: Download final video
    # ------------------------------------------------------------------
    log("Step 7: Downloading final video...")
    step_download(project, record_id, dest_dir_slash)

    log(f"Done! Record {record_id} processed successfully.")


if __name__ == "__main__":
    main()
