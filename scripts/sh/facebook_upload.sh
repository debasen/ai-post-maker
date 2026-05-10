#!/usr/bin/env bash
# facebook_upload.sh — Facebook Reels upload automation
# Converts .agents/workflows/facebook_upload.md into a deterministic shell script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source Framework
source "$SCRIPT_DIR/lib/framework.sh"

# ─── Page-aware BrowserOS helpers ──────────────────────────────────────────────

BROWSEROS_CLI="${BROWSEROS_CLI:-browseros-cli}"
PAGE_ID=""

_fb_bos() {
    local cmd="$1"
    shift
    local output
    local exit_code
    output=$("$BROWSEROS_CLI" "$cmd" "$@" 2>&1)
    exit_code=$?
    log_cmd "$BROWSEROS_CLI $cmd $*" "$output" "$exit_code"
    echo "$output"
    return $exit_code
}

fb_open_page() {
    local url="$1"
    log INFO "Opening new page: $url"
    local output
    output=$(_fb_bos open "$url" --json)
    local open_exit=$?
    if [ $open_exit -ne 0 ]; then
        log FATAL "Failed to open new page"
    fi
    PAGE_ID=$(echo "$output" | jq -r '.pageId // empty' 2>/dev/null)
    if [ -z "$PAGE_ID" ]; then
        log FATAL "Could not extract pageId from open response"
    fi
    log INFO "Page opened with ID: $PAGE_ID"
}

fb_snap() {
    _fb_bos snap -p "$PAGE_ID"
}

fb_eval() {
    local js="$1"
    local output
    output=$(_fb_bos eval -p "$PAGE_ID" "$js")
    local eval_exit=$?
    if [ $eval_exit -ne 0 ]; then
        log ERROR "fb_eval failed"
        return 1
    fi
    echo "$output"
}

fb_eval_result() {
    local js="$1"
    local output
    output=$(fb_eval "$js")
    # browseros-cli eval returns raw JS values (true, false, strings), not JSON objects.
    # Try .result if the output is a JSON object; otherwise return the raw value.
    echo "$output" | jq -r 'if type == "object" then .result // empty else . end' 2>/dev/null
}

fb_click() {
    local ref="$1"
    _fb_bos click -p "$PAGE_ID" "$ref"
}

fb_fill() {
    local ref="$1"
    local text="$2"
    _fb_bos fill -p "$PAGE_ID" "$ref" "$text"
}

fb_upload() {
    local ref="$1"
    local file="$2"
    _fb_bos upload -p "$PAGE_ID" "$ref" "$file"
}

fb_text() {
    _fb_bos text -p "$PAGE_ID"
}

fb_close_page() {
    _fb_bos close -p "$PAGE_ID"
}

fb_get_snap_ref() {
    local pattern="$1"
    local snapshot_text
    snapshot_text=$(fb_snap)
    local ref
    ref=$(echo "$snapshot_text" | grep -i "$pattern" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    return 1
}

# ─── Script-specific helpers ───────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") --project <ID> [options]

Options:
  --project <N>          Project ID (1-2). Required.
  --log-dir <path>       Directory for log files (default: ./logs/)
  --timeout <seconds>    Global timeout per phase (default: 300)
  --max-retries <N>      Max retries for flaky operations (default: 3)
  -h, --help             Show this help

Environment Variables:
  BROWSEROS_CLI          Path to browseros-cli binary (default: browseros-cli)
  LOG_LEVEL              DEBUG, INFO, WARN, ERROR (default: INFO)
EOF
}

# ─── Phase 1: Identify Project and Asset ───────────────────────────────────────

phase_1_identify_asset() {
    log_section "Phase 1: Identify Project and Asset"

    if [ -z "${PROJECT_ID:-}" ]; then
        log FATAL "--project is required"
    fi

    if [ "$PROJECT_ID" != "1" ] && [ "$PROJECT_ID" != "2" ]; then
        log FATAL "Invalid project ID: $PROJECT_ID (must be 1 or 2)"
    fi

    log INFO "Fetching mapped post for project $PROJECT_ID..."
    local mapped_output
    mapped_output=$(python3 "$REPO_ROOT/scripts/py/get_mapped_post.py" --project "$PROJECT_ID" --platform facebook 2>&1)
    local mapped_exit=$?
    log DEBUG "get_mapped_post exit=$mapped_exit output='$mapped_output'"

    if [ $mapped_exit -ne 0 ]; then
        log FATAL "get_mapped_post.py failed: $mapped_output"
    fi

    ASSET_ID=$(echo "$mapped_output" | awk '/^ID:/{print substr($0, index($0,$2))}')
    CAPTION=$(echo "$mapped_output" | awk 'BEGIN{found=0} /^Caption:/{found=1; sub(/^Caption:[[:space:]]*/, ""); print; next} found && /^ID:/{exit} found{print}')

    if [ -z "$ASSET_ID" ]; then
        log FATAL "No mapped asset found for project $PROJECT_ID"
    fi
    if [ -z "$CAPTION" ]; then
        log FATAL "No caption found for mapped asset"
    fi

    log INFO "Asset ID: $ASSET_ID"
    log INFO "Caption length: ${#CAPTION} chars"

    ASSET_PATH="$REPO_ROOT/project-$PROJECT_ID/assets/$ASSET_ID.mp4"
    log INFO "Asset path: $ASSET_PATH"

    if [ ! -f "$ASSET_PATH" ]; then
        log FATAL "Asset file not found: $ASSET_PATH"
    fi

    local fsize
    fsize=$(stat -f%z "$ASSET_PATH" 2>/dev/null || stat -c%s "$ASSET_PATH" 2>/dev/null)
    log INFO "Asset file size: $fsize bytes"
}

# ─── Phase 2: Read Facebook Reels URL ──────────────────────────────────────────

phase_2_read_url() {
    log_section "Phase 2: Read Facebook Reels URL"

    local json_file="$REPO_ROOT/project-$PROJECT_ID/grok_prompts.json"
    if [ ! -f "$json_file" ]; then
        log FATAL "grok_prompts.json not found: $json_file"
    fi

    FB_URL=$(python3 -c "import json; data=json.load(open('$json_file')); print(data['config']['facebook_reels_url'])" 2>/dev/null)
    if [ -z "$FB_URL" ] || [[ ! "$FB_URL" =~ ^https?:// ]]; then
        log FATAL "Invalid or missing facebook_reels_url in $json_file"
    fi

    log INFO "Facebook Reels URL: $FB_URL"
}

# ─── Phase 3: Open Facebook Reels Page ─────────────────────────────────────────

phase_3_open_page() {
    log_section "Phase 3: Open Facebook Reels Page"

    fb_open_page "$FB_URL"
    sleep 5

    log INFO "Taking snapshot..."
    local snapshot_text
    snapshot_text=$(fb_snap)
    log DEBUG "Snapshot lines: $(echo "$snapshot_text" | wc -l | tr -d ' ')"

    if ! echo "$snapshot_text" | grep -q 'button "Create reel"' && \
       ! echo "$snapshot_text" | grep -q 'link "Reels"'; then
        log FATAL "Snapshot missing 'Create reel' button and 'Reels' link"
    fi

    log INFO "Page loaded successfully"
}

# ─── Phase 4: Open "Create Reel" Dialog ────────────────────────────────────────

phase_4_open_dialog() {
    log_section "Phase 4: Open Create Reel Dialog"

    local create_ref
    create_ref=$(fb_get_snap_ref 'button "Create reel"')
    if [ -z "$create_ref" ]; then
        log FATAL "Could not find 'Create reel' button in snapshot"
    fi

    log INFO "Clicking 'Create reel' button (ref: $create_ref)..."
    fb_click "$create_ref"
    sleep 3

    log INFO "Verifying dialog opened..."
    local dialog_check
    dialog_check=$(fb_eval_result "document.querySelector('div[role=\"dialog\"] h2')?.innerText?.trim()?.includes('Create reel') || document.querySelector('div[aria-label=\"Create reel\"]') !== null || document.querySelector('div[role=\"dialog\"]')?.innerText?.includes('Add Video')")
    log DEBUG "Dialog check result: $dialog_check"

    if [ "$dialog_check" != "true" ]; then
        log FATAL "Create reel dialog not detected"
    fi

    log INFO "Create reel dialog confirmed"
}

# ─── Phase 5: Upload the Video File ────────────────────────────────────────────

phase_5_upload_video() {
    log_section "Phase 5: Upload the Video File"

    log INFO "Making file inputs visible..."
    fb_eval "document.querySelectorAll('input[type=\"file\"]').forEach(i => { i.style.display = 'block'; i.style.visibility = 'visible'; i.style.opacity = '1'; i.style.position = 'static'; i.style.width = '100px'; i.style.height = '50px'; i.style.zIndex = '999999'; });" > /dev/null

    log INFO "Taking snapshot to find Choose File buttons..."
    local snapshot_text
    snapshot_text=$(fb_snap)

    log INFO "Attempting upload via available Choose File buttons..."
    local choose_refs
    choose_refs=$(echo "$snapshot_text" | grep -i 'button "Choose File"' | sed -n 's/^\[\([0-9]*\)\].*/\1/p')

    local upload_success=0
    for ref in $choose_refs; do
        log INFO "Trying Choose File button ref: $ref"
        if fb_upload "$ref" "$ASSET_PATH" > /dev/null 2>&1; then
            upload_success=1
            log INFO "Upload initiated via ref: $ref"
            break
        fi
    done

    if [ "$upload_success" -eq 0 ]; then
        log FATAL "Could not upload video to any Choose File button"
    fi
    sleep 15

    log INFO "Polling for upload completion..."
    local attempt=1
    local max_attempts=16
    local upload_ready=0

    while [ "$attempt" -le "$max_attempts" ]; do
        local check_result
        check_result=$(fb_text)
        
        if echo "$check_result" | grep -q "Your reel is safe to publish!"; then
            log DEBUG "Upload check attempt $attempt/$max_attempts: true"
            upload_ready=1
            break
        fi

        log DEBUG "Upload check attempt $attempt/$max_attempts: false"
        log INFO "Upload still processing... (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done

    if [ "$upload_ready" -eq 0 ]; then
        log FATAL "Video upload did not complete after $max_attempts attempts"
    fi

    log INFO "Video uploaded successfully"
}

# ─── Phase 6: Navigate to Caption Screen ───────────────────────────────────────

phase_6_navigate_caption() {
    log_section "Phase 6: Navigate to Caption Screen"

    local next_ref
    next_ref=$(fb_get_snap_ref 'div "Next"')
    if [ -z "$next_ref" ]; then
        next_ref=$(fb_get_snap_ref 'button "Next"')
    fi
    if [ -z "$next_ref" ]; then
        next_ref=$(fb_get_snap_ref 'link "Next"')
    fi
    if [ -z "$next_ref" ]; then
        log FATAL "Could not find 'Next' button in snapshot"
    fi

    log INFO "Clicking 'Next' button (ref: $next_ref)..."
    fb_click "$next_ref"
    sleep 3

    log INFO "Verifying caption screen..."
    local caption_check
    caption_check=$(fb_eval_result "(function() { return !!document.querySelector('[contenteditable=\"true\"]') || !!document.querySelector('div[role=\"textbox\"]') || !!document.querySelector('textarea') || !!document.querySelector('[aria-placeholder*=\"Describe your reel\"]'); })()")
    log DEBUG "Caption screen check: $caption_check"

    if [ "$caption_check" != "true" ]; then
        log FATAL "Caption textbox not found"
    fi

    log INFO "Caption screen ready"
}

# ─── Phase 7: Enter the Caption ────────────────────────────────────────────────

phase_7_enter_caption() {
    log_section "Phase 7: Enter the Caption"

    log INFO "Finding caption textbox..."
    local textbox_ref
    # Try specific patterns first, then fall back to generic roles
    textbox_ref=$(fb_get_snap_ref 'textbox "Describe')
    if [ -z "$textbox_ref" ]; then
        textbox_ref=$(fb_get_snap_ref 'textbox')
    fi
    if [ -z "$textbox_ref" ]; then
        textbox_ref=$(fb_get_snap_ref 'paragraph')
    fi
    if [ -z "$textbox_ref" ]; then
        log FATAL "Could not find caption textbox in snapshot"
    fi

    log INFO "Typing caption into textbox (ref: $textbox_ref)..."
    if fb_fill "$textbox_ref" "$CAPTION"; then
        log INFO "Fill command succeeded"
    else
        log WARN "Fill command failed (element may not support fill). Falling back to JS insertHTML..."

        # Focus the textbox first
        local focus_check
        focus_check=$(fb_eval_result "(function() { var el = document.querySelector('[contenteditable=\"true\"]') || document.querySelector('div[role=\"textbox\"]') || document.querySelector('textarea') || document.querySelector('[aria-placeholder*=\"Describe your reel\"]'); if (el) { el.click(); el.focus(); } return !!el; })()")
        if [ "$focus_check" != "true" ]; then
            log FATAL "Failed to focus caption textbox for fallback"
        fi

        # Clear existing text
        fb_eval "document.activeElement.innerHTML = '';" > /dev/null

        # JSON-encode caption for safe JS injection
        local json_caption
        json_caption=$(printf '%s' "$CAPTION" | jq -Rs '.')

        # Use insertHTML with <br> tags to preserve line breaks in contenteditable
        fb_eval "(function() { var caption = $json_caption; var el = document.activeElement; el.focus(); var htmlCaption = caption.replace(/\n/g, '<br>').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); document.execCommand('insertHTML', false, htmlCaption); })()" > /dev/null
    fi

    sleep 2

    log INFO "Verifying caption was entered..."
    local caption_verify
    caption_verify=$(fb_eval_result "(function() { var el = document.querySelector('[contenteditable=\"true\"]') || document.querySelector('div[role=\"textbox\"]') || document.querySelector('textarea') || document.querySelector('[aria-placeholder*=\"Describe your reel\"]'); var text = el?.innerText || ''; return text.length > 50; })()")
    if [ "$caption_verify" != "true" ]; then
        log FATAL "Caption verification failed (text too short or missing)"
    fi

    log INFO "Caption entered successfully"
}

# ─── Phase 8: Navigate to Final Review Screen ──────────────────────────────────

phase_8_final_review() {
    log_section "Phase 8: Navigate to Final Review Screen"

    local next_ref
    next_ref=$(fb_get_snap_ref 'div "Next"')
    if [ -z "$next_ref" ]; then
        next_ref=$(fb_get_snap_ref 'button "Next"')
    fi
    if [ -z "$next_ref" ]; then
        next_ref=$(fb_get_snap_ref 'link "Next"')
    fi
    if [ -z "$next_ref" ]; then
        log FATAL "Could not find 'Next' button for final review"
    fi

    log INFO "Clicking 'Next' button (ref: $next_ref)..."
    fb_click "$next_ref"
    sleep 3

    log INFO "Verifying final review screen..."
    local review_text
    review_text=$(fb_text)
    
    local has_heading=0
    local has_post=0
    local has_safe=0
    
    if echo "$review_text" | grep -q "Reel settings"; then has_heading=1; fi
    if echo "$review_text" | grep -q "Post"; then has_post=1; fi
    if echo "$review_text" | grep -q "Your reel is safe to publish!"; then has_safe=1; fi
    
    log DEBUG "Final review check: heading=$has_heading, post=$has_post, safe=$has_safe"
    
    if [ "$has_heading" -eq 1 ] && [ "$has_post" -eq 1 ]; then
        log INFO "Final review screen confirmed"
    else
        log FATAL "Final review screen not detected (missing 'Reel settings' or 'Post')"
    fi
}

# ─── Phase 9: Manual Review ────────────────────────────────────────────────────

phase_9_manual_review() {
    log_section "Phase 9: Manual Review"

    log INFO "Checking Post button state..."
    local post_check
    post_check=$(fb_eval_result "(function() { var postBtn = Array.from(document.querySelectorAll('div[role=\"button\"], button')).find(function(b) { return b.innerText?.includes('Post'); }); return postBtn && !postBtn.disabled && postBtn.offsetParent !== null; })()")
    log DEBUG "Post button check (1st attempt): $post_check"

    if [ "$post_check" != "true" ]; then
        log WARN "Post button not ready, waiting 3 seconds..."
        sleep 3
        post_check=$(fb_eval_result "(function() { var postBtn = Array.from(document.querySelectorAll('div[role=\"button\"], button')).find(function(b) { return b.innerText?.includes('Post'); }); return postBtn && !postBtn.disabled && postBtn.offsetParent !== null; })()")
        log DEBUG "Post button check (2nd attempt): $post_check"
        if [ "$post_check" != "true" ]; then
            log FATAL "Post button is not enabled after retry"
        fi
    fi

    log INFO "Post button is enabled and ready"
    log INFO ""
    log INFO "============================================"
    log INFO "  MANUAL REVIEW REQUIRED"
    log INFO "============================================"
    log INFO "  Asset ID: $ASSET_ID"
    log INFO "  Project:  project-$PROJECT_ID"
    log INFO "  Status:   Ready to publish"
    log INFO ""
    log INFO "  Please review the reel in the browser."
    log INFO "  DO NOT proceed until you manually click"
    log INFO "  the 'Post' button and confirm success."
    log INFO "============================================"
    log INFO ""
}

# ─── Phase 10: Mark Record as Done ─────────────────────────────────────────────

phase_10_mark_done() {
    log_section "Phase 10: Mark Record as Done"

    read -r -p "Have you successfully published the reel? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log WARN "User did not confirm publication. Skipping tracker update."
        return 1
    fi

    log INFO "Marking asset $ASSET_ID as uploaded for facebook..."
    local tracker_output
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_uploaded "$ASSET_ID" facebook 2>&1)
    local tracker_exit=$?
    log DEBUG "Tracker output: $tracker_output"

    if [ $tracker_exit -ne 0 ]; then
        log FATAL "Tracker update failed: $tracker_output"
    fi

    log INFO "Record $ASSET_ID marked as uploaded for facebook in project-$PROJECT_ID/grok_prompts.json"
}

# ─── Phase 11: Close Browser Tab ───────────────────────────────────────────────

phase_11_close_tab() {
    log_section "Phase 11: Close Browser Tab"

    fb_close_page
    log INFO "Browser tab closed"
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    framework_setup "$@"

    phase_1_identify_asset
    phase_2_read_url
    phase_3_open_page
    phase_4_open_dialog
    phase_5_upload_video
    phase_6_navigate_caption
    phase_7_enter_caption
    phase_8_final_review
    phase_9_manual_review
    phase_10_mark_done
    phase_11_close_tab

    log_section "Complete"
    log INFO "Facebook upload workflow finished for project-$PROJECT_ID"
    log INFO "Log file: $LOG_FILE"
}

main "$@"
