#!/usr/bin/env python3
"""
instagram_follow_runner.py — Scripted Instagram follow automation (no AI required).

Converts the instagram_follow_suggestions workflow into a fully scripted Python
runner using browseros-cli for browser control.

Usage
-----
  # Follow from the explore/suggestions page (default)
  python3 scripts/py/instagram_follow_runner.py

  # Follow from a specific profile's followers list
  python3 scripts/py/instagram_follow_runner.py --profile https://www.instagram.com/someuser/

  # Multiple passes (page reloads between passes in explore mode)
  python3 scripts/py/instagram_follow_runner.py --passes 2
  python3 scripts/py/instagram_follow_runner.py --profile https://www.instagram.com/someuser/ --passes 2

  # Dry run (prints steps but does not click anything)
  python3 scripts/py/instagram_follow_runner.py --dry-run
  python3 scripts/py/instagram_follow_runner.py --profile https://www.instagram.com/someuser/ --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
JS_DIR = os.path.join(REPO_ROOT, "scripts", "js")

INSTAGRAM_FOLLOW_JS = os.path.join(JS_DIR, "instagram_follow.min.js")

EXPLORE_URL = "https://www.instagram.com/explore/people/"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

def log(msg: str):
    print(f"[instagram_follow] {msg}", flush=True)


def die(msg: str, code: int = 1):
    print(f"[instagram_follow] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


# ---------------------------------------------------------------------------
# browseros-cli helpers
# ---------------------------------------------------------------------------

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
    Returns the parsed JSON result.
    """
    cmd = ["browseros-cli", "eval", js_code, "--json"]
    result = run_browseros_cli(cmd)

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
    if not os.path.exists(path):
        die(f"JS library not found: {path}. Did you run the build step?")
    with open(path, "r") as f:
        return f.read()


def build_eval(fn_call: str) -> str:
    """Prepend the instagram_follow library, then wrap fn_call in an async IIFE."""
    lib_js = load_js(INSTAGRAM_FOLLOW_JS)
    return (
        "(async () => {\n"
        f"  {lib_js}\n"
        f"  return await {fn_call};\n"
        "})();"
    )


# ---------------------------------------------------------------------------
# Navigation helpers
# ---------------------------------------------------------------------------

def step_open_page(url: str) -> str:
    """Open a new browser tab at the given URL. Returns the page ID."""
    log(f"Opening new tab: {url}")
    cmd = ["browseros-cli", "open", url, "--json"]
    result = run_browseros_cli(cmd)
    raw = result.stdout.strip() if result.returncode == 0 else ""
    try:
        parsed = json.loads(raw)
        page_id = parsed.get("pageId") or parsed.get("id") or parsed.get("tabId") or ""
        if page_id:
            log(f"Page opened. ID: {page_id}")
        else:
            log("Page opened (could not parse page ID).")
        return str(page_id)
    except Exception:
        log("Page opened (response received).")
        return ""


def step_navigate(url: str):
    """Navigate the active tab to a URL (uses browseros-cli nav)."""
    log(f"Navigating to: {url}")
    browseros(["nav", url])


def step_reload():
    """Reload the active tab."""
    log("Reloading page...")
    browseros(["reload"])


def step_wait(seconds: int, reason: str = ""):
    msg = f"Waiting {seconds}s{' — ' + reason if reason else ''}..."
    log(msg)
    time.sleep(seconds)


# ---------------------------------------------------------------------------
# Core follow steps
# ---------------------------------------------------------------------------

def run_explore_pass(pass_num: int, dry_run: bool) -> dict:
    """
    Execute one follow pass on the explore/people page.
    Returns the results dict from the JS function.
    """
    log(f"─── Explore pass #{pass_num} ───")
    if dry_run:
        log("DRY-RUN: Would call followExploreSuggestions()")
        return {"attempted": 0, "succeeded": 0, "skipped": 0, "errors": [], "dry_run": True}

    result = browseros_eval(build_eval("followExploreSuggestions()"))
    log(f"followExploreSuggestions result: {result}")

    if isinstance(result, dict) and "error" in result:
        die(f"Explore follow failed: {result['error']}")

    return result or {}


def run_profile_pass(dry_run: bool) -> dict:
    """
    Execute one follow pass from the profile followers modal.
    Returns the results dict from the JS function.
    """
    log("─── Profile followers pass ───")
    if dry_run:
        log("DRY-RUN: Would call followProfileFollowers()")
        return {"attempted": 0, "succeeded": 0, "skipped": 0, "errors": [], "dry_run": True, "modalOpened": False}

    result = browseros_eval(build_eval("followProfileFollowers()"))
    log(f"followProfileFollowers result: {result}")

    if isinstance(result, dict) and "error" in result:
        die(f"Profile follow failed: {result['error']}")

    return result or {}


# ---------------------------------------------------------------------------
# Results summarizer
# ---------------------------------------------------------------------------

def summarize(all_results: list):
    total_attempted = sum(r.get("attempted", 0) for r in all_results)
    total_succeeded = sum(r.get("succeeded", 0) for r in all_results)
    total_errors = sum(len(r.get("errors", [])) for r in all_results)

    print()
    print("═" * 55)
    print(f"  📊  Instagram Follow — Summary")
    print(f"  Passes run:        {len(all_results)}")
    print(f"  Total attempted:   {total_attempted}")
    print(f"  Total succeeded:   {total_succeeded}")
    print(f"  Total errors:      {total_errors}")
    print("═" * 55)
    print()

    if total_errors > 0:
        for i, r in enumerate(all_results, 1):
            for e in r.get("errors", []):
                log(f"Pass {i} error at index {e.get('index')}: {e.get('error')}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Instagram follow runner. "
            "With no arguments, follows suggestions from the explore/people page. "
            "Pass --profile <url> to follow from a specific profile's followers list."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Follow from explore/suggestions page (default)\n"
            "  python3 instagram_follow_runner.py\n\n"
            "  # Follow from a specific profile's followers\n"
            "  python3 instagram_follow_runner.py --profile https://www.instagram.com/someuser/\n\n"
            "  # Two passes on the explore page\n"
            "  python3 instagram_follow_runner.py --passes 2\n\n"
            "  # Dry run\n"
            "  python3 instagram_follow_runner.py --dry-run\n"
        ),
    )
    parser.add_argument(
        "--profile",
        metavar="URL",
        default=None,
        help=(
            "Instagram profile URL to follow from (e.g. https://www.instagram.com/someuser/). "
            "When omitted, follows from the explore/people suggestions page."
        ),
    )
    parser.add_argument(
        "--passes",
        type=int,
        default=1,
        help=(
            "Number of follow passes to run (default: 1). "
            "For explore mode, the page is reloaded between passes. "
            "For profile mode, the followers modal is re-opened between passes."
        ),
    )
    parser.add_argument(
        "--reload-wait",
        type=int,
        default=4,
        help="Seconds to wait after page reload/navigation before running each pass (default: 4).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print all steps without actually clicking any follow buttons.",
    )
    args = parser.parse_args()

    # ── Validate args ────────────────────────────────────────
    if args.passes < 1:
        die("--passes must be >= 1.")

    if args.dry_run:
        log("DRY-RUN mode enabled — no buttons will be clicked.")

    # ──────────────────────────────────────────────────────────
    # PROFILE MODE  (--profile <url> was provided)
    # ──────────────────────────────────────────────────────────
    if args.profile:
        log(f"Mode: profile | Profile URL: {args.profile} | Passes: {args.passes}")

        all_results = []

        for pass_num in range(1, args.passes + 1):
            # Navigate to profile for each pass (re-opens the modal fresh)
            step_navigate(args.profile)
            step_wait(args.reload_wait, "waiting for profile page to load")

            result = run_profile_pass(args.dry_run)
            all_results.append(result)

            succeeded = result.get("succeeded", 0)
            modal_opened = result.get("modalOpened", False)
            log(f"Pass #{pass_num} complete: {succeeded} accounts followed. Modal opened: {modal_opened}")

            if pass_num < args.passes:
                step_wait(3, "cooldown before next pass")

        summarize(all_results)

    # ──────────────────────────────────────────────────────────
    # EXPLORE MODE  (default — no --profile given)
    # ──────────────────────────────────────────────────────────
    else:
        log(f"Mode: explore | Passes: {args.passes}")

        # Open the explore/people page in a new tab
        step_open_page(EXPLORE_URL)
        step_wait(args.reload_wait, "waiting for page to load")

        all_results = []

        for pass_num in range(1, args.passes + 1):
            if pass_num > 1:
                # Reload to get fresh suggestions
                step_reload()
                step_wait(args.reload_wait, "waiting for page to reload")

            result = run_explore_pass(pass_num, args.dry_run)
            all_results.append(result)

            succeeded = result.get("succeeded", 0)
            log(f"Pass #{pass_num} complete: {succeeded} accounts followed.")

        summarize(all_results)


if __name__ == "__main__":
    main()
