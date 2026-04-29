#!/usr/bin/env python3
"""Test harness for grok_automation workflow scenarios."""

import json
import subprocess
import os
import sys
import copy

PROJECT_PATH = "/Users/dsen/Projects/ai-post-maker/project-2/grok_prompts.json"
BACKUP_PATH = "/Users/dsen/Projects/ai-post-maker/project-2/grok_prompts.json.backup"

def load_data():
    with open(PROJECT_PATH, "r") as f:
        return json.load(f)

def save_data(data):
    with open(PROJECT_PATH, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def restore_backup():
    with open(BACKUP_PATH, "r") as f:
        data = json.load(f)
    save_data(data)
    print("[RESTORED] Original data restored from backup.")

def run_tracker_cmd(cmd_args):
    full_cmd = ["python3", "shared/grok_tracker.py", "--project", "2"] + cmd_args
    result = subprocess.run(full_cmd, capture_output=True, text=True, cwd="/Users/dsen/Projects/ai-post-maker")
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()
    try:
        parsed = json.loads(stdout) if stdout else {}
    except json.JSONDecodeError:
        parsed = {"raw_stdout": stdout, "raw_stderr": stderr}
    return parsed, stdout, stderr

def set_prompt_status(prompt_id, status, extra_fields=None):
    data = load_data()
    for item in data["prompts"]:
        if item["id"] == prompt_id:
            item["status"] = status
            if extra_fields:
                item.update(extra_fields)
            save_data(data)
            return item
    return None

def reset_all_pending():
    """Reset all prompts to pending (for clean tests)."""
    data = load_data()
    for item in data["prompts"]:
        if item.get("status") not in ("completed",):
            item["status"] = "pending"
            # Remove warning/failure timestamps
            for key in ["video_warning_at", "image_warning_at", "video_failed_at", "image_failed_at", "failed_at"]:
                item.pop(key, None)
    save_data(data)

def print_section(title):
    print("\n" + "="*70)
    print(f"  {title}")
    print("="*70)

# ─────────────────────────────────────────────────────────────
# SCENARIO TESTS
# ─────────────────────────────────────────────────────────────

def test_scenario_1_pending_default():
    """Scenario 1: pending item with NO video_prompt, NO video_type (default Make video)."""
    print_section("SCENARIO 1: Full Flow - pending + default 'Make video'")
    restore_backup()
    
    # Find a prompt without video_prompt and without video_type, set to pending
    data = load_data()
    target = None
    for item in data["prompts"]:
        if item["id"] == 95:  # id=95 has no video_prompt, no video_type
            target = item
            break
    
    if target:
        target["status"] = "pending"
        for key in ["video_warning_at", "image_warning_at", "video_failed_at", "image_failed_at", "failed_at"]:
            target.pop(key, None)
        # Ensure no video_prompt or video_type
        target.pop("video_prompt", None)
        target.pop("video_type", None)
        save_data(data)
        
        # Set all other pending to some non-pending state so 95 is picked
        data = load_data()
        for item in data["prompts"]:
            if item["id"] != 95 and item.get("status") == "pending":
                item["status"] = "hold_for_test"
        save_data(data)
        
        result, stdout, stderr = run_tracker_cmd(["get_next"])
        print(f"get_next result: {json.dumps(result, indent=2)}")
        
        checks = []
        checks.append(("id == 95", result.get("id") == 95))
        checks.append(("status == pending", result.get("status") == "pending"))
        checks.append(("retry_mode == false", result.get("retry_mode") == False))
        checks.append(("no video_prompt", "video_prompt" not in result))
        checks.append(("no video_type", "video_type" not in result))
        checks.append(("retry_reason not present", "retry_reason" not in result))
        
        print("Checks:")
        for desc, ok in checks:
            print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
        return all(c[1] for c in checks)
    return False

def test_scenario_2_pending_custom_video_prompt():
    """Scenario 2: pending item WITH video_prompt (custom video prompt mode)."""
    print_section("SCENARIO 2: Full Flow - pending + custom video_prompt")
    restore_backup()
    
    data = load_data()
    # Use id=94 which has video_prompt
    target = None
    for item in data["prompts"]:
        if item["id"] == 94:
            target = item
            break
    
    if target:
        target["status"] = "pending"
        for key in ["video_warning_at", "image_warning_at", "video_failed_at", "image_failed_at", "failed_at"]:
            target.pop(key, None)
        save_data(data)
        
        # Block others
        data = load_data()
        for item in data["prompts"]:
            if item["id"] != 94 and item.get("status") == "pending":
                item["status"] = "hold_for_test"
        save_data(data)
        
        result, stdout, stderr = run_tracker_cmd(["get_next"])
        print(f"get_next result: {json.dumps(result, indent=2)}")
        
        checks = []
        checks.append(("id == 94", result.get("id") == 94))
        checks.append(("retry_mode == false", result.get("retry_mode") == False))
        checks.append(("video_prompt present", "video_prompt" in result and result["video_prompt"]))
        checks.append(("no video_type", "video_type" not in result or not result.get("video_type")))
        
        print("Checks:")
        for desc, ok in checks:
            print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
        return all(c[1] for c in checks)
    return False

def test_scenario_3_pending_spicy():
    """Scenario 3: pending item WITH video_type='spicy'."""
    print_section("SCENARIO 3: Full Flow - pending + video_type='spicy'")
    restore_backup()
    
    data = load_data()
    # Use id=75 which has video_type: spicy
    target = None
    for item in data["prompts"]:
        if item["id"] == 75:
            target = item
            break
    
    if target:
        target["status"] = "pending"
        for key in ["video_warning_at", "image_warning_at", "video_failed_at", "image_failed_at", "failed_at"]:
            target.pop(key, None)
        save_data(data)
        
        # Block others
        data = load_data()
        for item in data["prompts"]:
            if item["id"] != 75 and item.get("status") == "pending":
                item["status"] = "hold_for_test"
        save_data(data)
        
        result, stdout, stderr = run_tracker_cmd(["get_next"])
        print(f"get_next result: {json.dumps(result, indent=2)}")
        
        checks = []
        checks.append(("id == 75", result.get("id") == 75))
        checks.append(("retry_mode == false", result.get("retry_mode") == False))
        checks.append(("video_type == spicy", result.get("video_type") == "spicy"))
        
        print("Checks:")
        for desc, ok in checks:
            print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
        return all(c[1] for c in checks)
    return False

def test_scenario_4_retry_video_warning():
    """Scenario 4: video_warning retry item should be picked first."""
    print_section("SCENARIO 4: Retry Flow - video_warning")
    restore_backup()
    
    data = load_data()
    # Set id=94 to video_warning, id=95 to pending
    for item in data["prompts"]:
        if item["id"] == 94:
            item["status"] = "video_warning"
            item["post_url"] = "https://grok.com/imagine/post/test-video-warning"
            item["video_warning_at"] = "2026-04-29T10:00:00Z"
        elif item["id"] == 95:
            item["status"] = "pending"
        elif item.get("status") == "pending":
            item["status"] = "hold_for_test"
    save_data(data)
    
    result, stdout, stderr = run_tracker_cmd(["get_next"])
    print(f"get_next result: {json.dumps(result, indent=2)}")
    
    checks = []
    checks.append(("id == 94 (video_warning picked before pending)", result.get("id") == 94))
    checks.append(("retry_mode == true", result.get("retry_mode") == True))
    checks.append(("retry_reason == video_warning", result.get("retry_reason") == "video_warning"))
    checks.append(("post_url present", "post_url" in result and result["post_url"]))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_5_retry_image_warning():
    """Scenario 5: image_warning retry item should be picked second (after video_warning)."""
    print_section("SCENARIO 5: Retry Flow - image_warning")
    restore_backup()
    
    data = load_data()
    # Set id=94 to image_warning, id=95 to pending
    for item in data["prompts"]:
        if item["id"] == 94:
            item["status"] = "image_warning"
            item["post_url"] = "https://grok.com/imagine/post/test-image-warning"
            item["image_warning_at"] = "2026-04-29T10:00:00Z"
        elif item["id"] == 95:
            item["status"] = "pending"
        elif item.get("status") == "pending":
            item["status"] = "hold_for_test"
    save_data(data)
    
    result, stdout, stderr = run_tracker_cmd(["get_next"])
    print(f"get_next result: {json.dumps(result, indent=2)}")
    
    checks = []
    checks.append(("id == 94 (image_warning picked before pending)", result.get("id") == 94))
    checks.append(("retry_mode == true", result.get("retry_mode") == True))
    checks.append(("retry_reason == image_warning", result.get("retry_reason") == "image_warning"))
    checks.append(("post_url present", "post_url" in result and result["post_url"]))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_6_retry_priority():
    """Scenario 6: video_warning should be picked BEFORE image_warning."""
    print_section("SCENARIO 6: Retry Priority - video_warning before image_warning")
    restore_backup()
    
    data = load_data()
    # Set id=94 to video_warning, id=95 to image_warning
    for item in data["prompts"]:
        if item["id"] == 94:
            item["status"] = "video_warning"
            item["post_url"] = "https://grok.com/imagine/post/test-video-warn"
            item["video_warning_at"] = "2026-04-29T10:00:00Z"
        elif item["id"] == 95:
            item["status"] = "image_warning"
            item["post_url"] = "https://grok.com/imagine/post/test-image-warn"
            item["image_warning_at"] = "2026-04-29T10:00:00Z"
        elif item.get("status") == "pending":
            item["status"] = "hold_for_test"
    save_data(data)
    
    result, stdout, stderr = run_tracker_cmd(["get_next"])
    print(f"get_next result: {json.dumps(result, indent=2)}")
    
    checks = []
    checks.append(("video_warning (id=94) picked before image_warning (id=95)", result.get("id") == 94))
    checks.append(("retry_reason == video_warning", result.get("retry_reason") == "video_warning"))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_7_terminal_states_invisible():
    """Scenario 7: video_failed and image_failed should be invisible to get_next."""
    print_section("SCENARIO 7: Terminal states invisible to get_next")
    restore_backup()
    
    data = load_data()
    # Set ALL to terminal or hold, no pending/warning
    for item in data["prompts"]:
        if item["id"] == 55:
            item["status"] = "video_failed"
            item["post_url"] = "https://grok.com/imagine/post/test-vf"
            item["video_failed_at"] = "2026-04-29T10:00:00Z"
        elif item["id"] == 56:
            item["status"] = "image_failed"
            item["post_url"] = "https://grok.com/imagine/post/test-if"
            item["image_failed_at"] = "2026-04-29T10:00:00Z"
        elif item.get("status") == "pending":
            item["status"] = "hold_for_test"
    save_data(data)
    
    result, stdout, stderr = run_tracker_cmd(["get_next"])
    print(f"get_next result: {json.dumps(result, indent=2)}")
    
    checks = []
    checks.append(("error returned", "error" in result))
    checks.append(("error says 'No pending or retry prompts'", "No pending or retry prompts" in result.get("error", "")))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_8_tracker_complete():
    """Scenario 8: Test 'complete' command."""
    print_section("SCENARIO 8: Tracker command - complete")
    restore_backup()
    
    # Set id=94 to pending
    data = load_data()
    for item in data["prompts"]:
        if item["id"] == 94:
            item["status"] = "pending"
        elif item.get("status") == "pending":
            item["status"] = "hold_for_test"
    save_data(data)
    
    result, stdout, stderr = run_tracker_cmd([
        "complete", "94",
        "https://grok.com/imagine/post/video-94",
        "https://grok.com/imagine/post/post-94"
    ])
    print(f"complete result: {json.dumps(result, indent=2)}")
    
    data = load_data()
    item_94 = next((i for i in data["prompts"] if i["id"] == 94), None)
    
    checks = []
    checks.append(("success == true", result.get("success") == True))
    checks.append(("status now 'completed'", item_94.get("status") == "completed"))
    checks.append(("video_url set", item_94.get("video_url") == "https://grok.com/imagine/post/video-94"))
    checks.append(("post_url set", item_94.get("post_url") == "https://grok.com/imagine/post/post-94"))
    checks.append(("executed_at set", "executed_at" in item_94))
    checks.append(("video_warning_at removed", "video_warning_at" not in item_94))
    checks.append(("image_warning_at removed", "image_warning_at" not in item_94))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_9_tracker_mark_video_warning():
    """Scenario 9: Test mark_video_warning command."""
    print_section("SCENARIO 9: Tracker command - mark_video_warning")
    restore_backup()
    
    result, stdout, stderr = run_tracker_cmd([
        "mark_video_warning", "95", "https://grok.com/imagine/post/test-vw"
    ])
    print(f"mark_video_warning result: {json.dumps(result, indent=2)}")
    
    data = load_data()
    item_95 = next((i for i in data["prompts"] if i["id"] == 95), None)
    
    checks = []
    checks.append(("success == true", result.get("success") == True))
    checks.append(("status now 'video_warning'", item_95.get("status") == "video_warning"))
    checks.append(("post_url set", item_95.get("post_url") == "https://grok.com/imagine/post/test-vw"))
    checks.append(("video_warning_at set", "video_warning_at" in item_95))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_10_tracker_mark_image_warning():
    """Scenario 10: Test mark_image_warning command."""
    print_section("SCENARIO 10: Tracker command - mark_image_warning")
    restore_backup()
    
    result, stdout, stderr = run_tracker_cmd([
        "mark_image_warning", "95", "https://grok.com/imagine/post/test-iw"
    ])
    print(f"mark_image_warning result: {json.dumps(result, indent=2)}")
    
    data = load_data()
    item_95 = next((i for i in data["prompts"] if i["id"] == 95), None)
    
    checks = []
    checks.append(("success == true", result.get("success") == True))
    checks.append(("status now 'image_warning'", item_95.get("status") == "image_warning"))
    checks.append(("post_url set", item_95.get("post_url") == "https://grok.com/imagine/post/test-iw"))
    checks.append(("image_warning_at set", "image_warning_at" in item_95))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_11_tracker_mark_video_failed():
    """Scenario 11: Test mark_video_failed command."""
    print_section("SCENARIO 11: Tracker command - mark_video_failed")
    restore_backup()
    
    result, stdout, stderr = run_tracker_cmd([
        "mark_video_failed", "95", "https://grok.com/imagine/post/test-vfail"
    ])
    print(f"mark_video_failed result: {json.dumps(result, indent=2)}")
    
    data = load_data()
    item_95 = next((i for i in data["prompts"] if i["id"] == 95), None)
    
    checks = []
    checks.append(("success == true", result.get("success") == True))
    checks.append(("status now 'video_failed'", item_95.get("status") == "video_failed"))
    checks.append(("video_failed_at set", "video_failed_at" in item_95))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_12_tracker_mark_image_failed():
    """Scenario 12: Test mark_image_failed command."""
    print_section("SCENARIO 12: Tracker command - mark_image_failed")
    restore_backup()
    
    result, stdout, stderr = run_tracker_cmd([
        "mark_image_failed", "95", "https://grok.com/imagine/post/test-ifail"
    ])
    print(f"mark_image_failed result: {json.dumps(result, indent=2)}")
    
    data = load_data()
    item_95 = next((i for i in data["prompts"] if i["id"] == 95), None)
    
    checks = []
    checks.append(("success == true", result.get("success") == True))
    checks.append(("status now 'image_failed'", item_95.get("status") == "image_failed"))
    checks.append(("image_failed_at set", "image_failed_at" in item_95))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_13_retry_then_terminal():
    """Scenario 13: Simulate video_warning -> retry -> video_failed."""
    print_section("SCENARIO 13: Retry escalation - video_warning then video_failed")
    restore_backup()
    
    # Step 1: Mark as video_warning
    run_tracker_cmd(["mark_video_warning", "95", "https://grok.com/imagine/post/retry-1"])
    
    # Step 2: get_next should pick it (retry)
    result, _, _ = run_tracker_cmd(["get_next"])
    checks = []
    checks.append(("Step 1: get_next picks video_warning id=95", result.get("id") == 95))
    checks.append(("Step 1: retry_mode true", result.get("retry_mode") == True))
    
    # Step 3: Mark as video_failed (simulating retry failure)
    run_tracker_cmd(["mark_video_failed", "95", "https://grok.com/imagine/post/final-fail"])
    
    # Step 4: get_next should NOT pick it
    result2, _, _ = run_tracker_cmd(["get_next"])
    checks.append(("Step 2: get_next does NOT pick video_failed", result2.get("id") != 95))
    checks.append(("Step 2: error returned for no items", "error" in result2))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_14_get_config():
    """Scenario 14: get_config returns expected fields."""
    print_section("SCENARIO 14: get_config output validation")
    restore_backup()
    
    result, stdout, stderr = run_tracker_cmd(["get_config"])
    print(f"get_config result: {json.dumps(result, indent=2)}")
    
    checks = []
    checks.append(("thumbnail_id present", "thumbnail_id" in result))
    checks.append(("starting_url present", "starting_url" in result))
    checks.append(("starting_url contains thumbnail_id", result.get("thumbnail_id", "") in result.get("starting_url", "")))
    checks.append(("starting_url is grok.com URL", "grok.com/imagine/post/" in result.get("starting_url", "")))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_15_complete_cleans_timestamps():
    """Scenario 15: complete command cleans up old warning/failure timestamps."""
    print_section("SCENARIO 15: complete cleans warning timestamps")
    restore_backup()
    
    # Manually set id=95 with mixed warning timestamps
    data = load_data()
    for item in data["prompts"]:
        if item["id"] == 95:
            item["status"] = "video_warning"
            item["video_warning_at"] = "2026-04-29T10:00:00Z"
            item["image_warning_at"] = "2026-04-29T10:00:00Z"
            item["video_failed_at"] = "2026-04-29T10:00:00Z"
            item["failed_at"] = "2026-04-29T10:00:00Z"
    save_data(data)
    
    run_tracker_cmd(["complete", "95", "https://video", "https://post"])
    
    data = load_data()
    item_95 = next((i for i in data["prompts"] if i["id"] == 95), None)
    
    checks = []
    checks.append(("status == completed", item_95.get("status") == "completed"))
    checks.append(("video_warning_at removed", "video_warning_at" not in item_95))
    checks.append(("image_warning_at removed", "image_warning_at" not in item_95))
    checks.append(("video_failed_at removed", "video_failed_at" not in item_95))
    checks.append(("failed_at removed", "failed_at" not in item_95))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_16_js_automateGrokGeneration_mode_logic():
    """Scenario 16: Validate JS mode determination logic without browser."""
    print_section("SCENARIO 16: JS mode logic validation (static analysis)")
    
    # Read the JS and check the mode logic
    with open("/Users/dsen/Projects/ai-post-maker/shared/grok_automation.js", "r") as f:
        js_content = f.read()
    
    checks = []
    checks.append(("tonedDownRetry forces default_make_video", 
                   "if (tonedDownRetry) {" in js_content and "mode = 'default_make_video'" in js_content))
    checks.append(("hasVideoPrompt triggers custom_video_prompt",
                   "mode = 'custom_video_prompt'" in js_content))
    checks.append(("isSpicy triggers spicy mode",
                   "mode = 'spicy'" in js_content))
    checks.append(("skipImageGeneration skips runImageGeneration",
                   "if (!skipImageGeneration)" in js_content))
    checks.append(("retry strips custom prompt",
                   "tonedDownRetry ? null : videoPromptText" in js_content))
    checks.append(("retry strips spicy type",
                   "tonedDownRetry ? null : videoType" in js_content))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_17_workflow_step_3b_video_warning_params():
    """Scenario 17: Validate Step 3B-i params for video_warning retry match workflow spec."""
    print_section("SCENARIO 17: Step 3B-i video_warning retry params validation")
    
    with open("/Users/dsen/Projects/ai-post-maker/shared/grok_automation.js", "r") as f:
        js_content = f.read()
    
    # The workflow says for video_warning retry:
    # skipImageGeneration: true, tonedDownRetry: true, postUrl: <post_url>
    # The JS accepts these params
    checks = []
    checks.append(("JS accepts skipImageGeneration param", "skipImageGeneration" in js_content))
    checks.append(("JS accepts tonedDownRetry param", "tonedDownRetry" in js_content))
    checks.append(("JS accepts postUrl param", "postUrl" in js_content))
    checks.append(("skipImageGeneration=true skips image phase", 
                   "if (!skipImageGeneration)" in js_content))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_18_workflow_step_3b_image_warning_params():
    """Scenario 18: Validate Step 3B-ii params for image_warning retry match workflow spec."""
    print_section("SCENARIO 18: Step 3B-ii image_warning retry params validation")
    
    with open("/Users/dsen/Projects/ai-post-maker/shared/grok_automation.js", "r") as f:
        js_content = f.read()
    
    # The workflow says for image_warning retry:
    # skipImageGeneration: false, tonedDownRetry: true, postUrl: <post_url>
    checks = []
    checks.append(("JS accepts skipImageGeneration param", "skipImageGeneration" in js_content))
    checks.append(("JS accepts tonedDownRetry param", "tonedDownRetry" in js_content))
    checks.append(("skipImageGeneration=false runs image phase", 
                   "if (!skipImageGeneration)" in js_content))
    checks.append(("tonedDownRetry=true forces default mode",
                   "if (tonedDownRetry) {" in js_content and "mode = 'default_make_video'" in js_content))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_19_js_checkVideoCompletion():
    """Scenario 19: Validate checkVideoCompletion function exists and logic."""
    print_section("SCENARIO 19: checkVideoCompletion validation")
    
    with open("/Users/dsen/Projects/ai-post-maker/shared/grok_automation.js", "r") as f:
        js_content = f.read()
    
    checks = []
    checks.append(("checkVideoCompletion function exists", "async function checkVideoCompletion()" in js_content))
    checks.append(("Returns 'completed' status", "status: 'completed'" in js_content))
    checks.append(("Returns 'video_warning' status", "status: 'video_warning'" in js_content))
    checks.append(("detectModeration checks svg.lucide-eye-off", "svg.lucide-eye-off" in js_content))
    checks.append(("detectVideoSuccess checks video element", "videoElement" in js_content))
    checks.append(("detectVideoSuccess checks pauseBtn", "pauseBtn" in js_content))
    checks.append(("detectVideoSuccess checks downloadBtn", "downloadBtn" in js_content))
    checks.append(("Polling for up to 6 minutes", "videoCompletionMaxAttempts" in js_content))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def test_scenario_20_js_image_generation_polling():
    """Scenario 20: Validate image generation polling logic."""
    print_section("SCENARIO 20: Image generation polling validation")
    
    with open("/Users/dsen/Projects/ai-post-maker/shared/grok_automation.js", "r") as f:
        js_content = f.read()
    
    checks = []
    checks.append(("Waits up to 2 minutes for Make video", "imageGenerationMaxAttempts" in js_content))
    checks.append(("Checks for moderation during image gen", "detectModeration()" in js_content))
    checks.append(("Returns image_warning on moderation", "status: 'image_warning'" in js_content))
    checks.append(("Returns image_warning on timeout", "IMAGE_GENERATION_TIMEOUT" in js_content))
    checks.append(("findVisibleMakeVideoButton checks visibility", "findVisibleMakeVideoButton" in js_content))
    
    print("Checks:")
    for desc, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
    return all(c[1] for c in checks)

def run_all_tests():
    results = {}
    
    results["scenario_1_pending_default"] = test_scenario_1_pending_default()
    results["scenario_2_pending_custom_video"] = test_scenario_2_pending_custom_video_prompt()
    results["scenario_3_pending_spicy"] = test_scenario_3_pending_spicy()
    results["scenario_4_retry_video_warning"] = test_scenario_4_retry_video_warning()
    results["scenario_5_retry_image_warning"] = test_scenario_5_retry_image_warning()
    results["scenario_6_retry_priority"] = test_scenario_6_retry_priority()
    results["scenario_7_terminal_invisible"] = test_scenario_7_terminal_states_invisible()
    results["scenario_8_tracker_complete"] = test_scenario_8_tracker_complete()
    results["scenario_9_tracker_mark_video_warning"] = test_scenario_9_tracker_mark_video_warning()
    results["scenario_10_tracker_mark_image_warning"] = test_scenario_10_tracker_mark_image_warning()
    results["scenario_11_tracker_mark_video_failed"] = test_scenario_11_tracker_mark_video_failed()
    results["scenario_12_tracker_mark_image_failed"] = test_scenario_12_tracker_mark_image_failed()
    results["scenario_13_retry_escalation"] = test_scenario_13_retry_then_terminal()
    results["scenario_14_get_config"] = test_scenario_14_get_config()
    results["scenario_15_complete_cleans"] = test_scenario_15_complete_cleans_timestamps()
    results["scenario_16_js_mode_logic"] = test_scenario_16_js_automateGrokGeneration_mode_logic()
    results["scenario_17_step_3bi_params"] = test_scenario_17_workflow_step_3b_video_warning_params()
    results["scenario_18_step_3bii_params"] = test_scenario_18_workflow_step_3b_image_warning_params()
    results["scenario_19_js_checkVideoCompletion"] = test_scenario_19_js_checkVideoCompletion()
    results["scenario_20_js_image_polling"] = test_scenario_20_js_image_generation_polling()
    
    # Final restore
    restore_backup()
    
    print("\n" + "="*70)
    print("  FINAL RESULTS")
    print("="*70)
    passed = 0
    failed = 0
    for name, ok in results.items():
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print(f"  [{status}] {name}")
    print(f"\nTotal: {passed} passed, {failed} failed out of {len(results)}")
    
    return results

if __name__ == "__main__":
    run_all_tests()
