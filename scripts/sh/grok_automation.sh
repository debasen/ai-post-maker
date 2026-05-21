#!/usr/bin/env bash
# grok_automation.sh — Main Grok home automation script
# Converts .agents/workflows/grok_home_automation.md into a deterministic shell script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source Framework
source "$SCRIPT_DIR/lib/framework.sh"

# ─── Page-aware BrowserOS helpers ──────────────────────────────────────────────

BROWSEROS_CLI="${BROWSEROS_CLI:-browseros-cli}"
PAGE_ID=""

_grok_bos() {
    local cmd="$1"
    shift
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] browseros-cli $cmd $*"
        return 0
    fi
    local output
    local exit_code
    output=$("$BROWSEROS_CLI" "$cmd" "$@" 2>&1)
    exit_code=$?
    log_cmd "$BROWSEROS_CLI $cmd $*" "$output" "$exit_code"
    echo "$output"
    return $exit_code
}

grok_open_page() {
    local url="$1"
    log INFO "Opening new page: $url"
    local output
    local open_exit
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] Would open new page: $url"
        output='{"pageId":12345}'
        open_exit=0
    else
        output=$(_grok_bos open "$url" --json)
        open_exit=$?
    fi
    if [ $open_exit -ne 0 ]; then
        log FATAL "Failed to open new page"
    fi
    PAGE_ID=$(echo "$output" | jq -r '.pageId // empty' 2>/dev/null)
    if [ -z "$PAGE_ID" ]; then
        log FATAL "Could not extract pageId from open response"
    fi
    log INFO "Page opened with ID: $PAGE_ID"
}

grok_snap() {
    if [ "$DRY_RUN" = "1" ]; then
        echo '[9999] button "Download"'
        return 0
    fi
    _grok_bos snap -p "$PAGE_ID"
}

grok_eval() {
    local js="$1"
    if [ "$DRY_RUN" = "1" ]; then
        echo '{"result":"https://grok.com/imagine/post/dry-run-test"}'
        return 0
    fi
    _grok_bos eval -p "$PAGE_ID" "$js"
}

grok_click_at() { _grok_bos click-at -p "$PAGE_ID" "$1" "$2"; }
grok_click()    { _grok_bos click -p "$PAGE_ID" "$1"; }
grok_key()      { _grok_bos key -p "$PAGE_ID" "$1"; }

grok_text() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "Download"
        return 0
    fi
    _grok_bos text -p "$PAGE_ID"
}

grok_download() { _grok_bos download -p "$PAGE_ID" "$1" "$2"; }

grok_get_snap_ref() {
    local pattern="$1"
    local snapshot_text
    snapshot_text=$(grok_snap)
    local ref
    ref=$(echo "$snapshot_text" | grep -i "$pattern" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    return 1
}

grok_click_by_snap_pattern() {
    local pattern="$1"
    log DEBUG "grok_click_by_snap_pattern: pattern='$pattern'"
    local ref
    ref=$(grok_get_snap_ref "$pattern")
    local ref_exit=$?
    log DEBUG "grok_click_by_snap_pattern: ref='$ref' exit=$ref_exit"
    if [ $ref_exit -ne 0 ] || [ -z "$ref" ]; then
        log WARN "Could not find snapshot ref for pattern: $pattern"
        return 1
    fi
    grok_click "$ref"
}

grok_get_page_url() {
    local output
    output=$(grok_eval "window.location.href")
    echo "$output" | jq -r '.result // empty' 2>/dev/null || echo "$output"
}

grok_find_element_coords() {
    local selector="$1"
    if [ "$DRY_RUN" = "1" ]; then
        echo '{"found":true,"x":500,"y":400,"width":100,"height":50}'
        return 0
    fi
    local js
    js=$(cat <<EOF
(function() {
    var el = document.querySelector('$selector');
    if (!el) return JSON.stringify({found: false});
    var rect = el.getBoundingClientRect();
    return JSON.stringify({
        found: true,
        x: rect.left + rect.width / 2,
        y: rect.top + rect.height / 2,
        width: rect.width,
        height: rect.height
    });
})()
EOF
)
    local output
    output=$(grok_eval "$js")
    echo "$output"
}

grok_find_element() {
    local selector="$1"
    local timeout="${2:-30}"
    local interval=2
    local elapsed=0
    log DEBUG "grok_find_element: selector='$selector' timeout=${timeout}s"
    while [ "$elapsed" -lt "$timeout" ]; do
        local output
        output=$(grok_find_element_coords "$selector")
        local coords_exit=$?
        log DEBUG "grok_find_element: attempt elapsed=${elapsed}s exit=$coords_exit output='${output:0:120}'"
        if [ "$coords_exit" -eq 2 ]; then
            log ERROR "CDP session lost, aborting element search for '$selector'"
            return 2
        fi
        if [ $coords_exit -eq 0 ]; then
            local found
            found=$(echo "$output" | jq -r '.found // false' 2>/dev/null)
            if [ "$found" = "true" ]; then
                log INFO "Element found: selector='$selector' coords=$(echo "$output" | jq -c '{x,y}')"
                echo "$output"
                return 0
            fi
            log DEBUG "grok_find_element: found=false, retrying..."
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    log WARN "Element not found: $selector (timeout ${timeout}s)"
    return 1
}

grok_type_text() {
    local text="$1"
    local input_info
    input_info=$(grok_find_element "$SELECTOR_INPUT" 10)
    local find_exit=$?
    if [ $find_exit -ne 0 ] || [ -z "$input_info" ]; then
        log ERROR "Could not find input coordinates"
        return 1
    fi
    local input_x input_y
    input_x=$(echo "$input_info" | jq -r '.x // empty' 2>/dev/null)
    input_y=$(echo "$input_info" | jq -r '.y // empty' 2>/dev/null)

    if [ -n "$input_x" ] && [ -n "$input_y" ]; then
        grok_click_at "$input_x" "$input_y"
    else
        log ERROR "Could not find input coordinates"
        return 1
    fi

    local escaped_text
    escaped_text=$(echo "$text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    local js
    js="(function() { var el = document.querySelector('$SELECTOR_INPUT'); if (!el) return JSON.stringify({success: false, error: 'not found'}); el.innerText = \"$escaped_text\"; el.dispatchEvent(new Event('input', {bubbles: true})); return JSON.stringify({success: true}); })()"

    grok_eval "$js"
}

grok_check_image_preference() {
    if [ "$DRY_RUN" = "1" ]; then return 1; fi
    local heading_text
    heading_text=$(grok_eval "(function() { var h = document.evaluate(\"//h3[contains(text(), 'Which image do you prefer to keep?')]\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue; return h ? h.innerText.trim() : ''; })()")
    heading_text=$(echo "$heading_text" | jq -r '.result // empty' 2>/dev/null || echo "$heading_text")
    if echo "$heading_text" | grep -q "Which image do you prefer to keep"; then
        return 0
    fi
    return 1
}

grok_handle_image_preference() {
    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Would check for image preference dialog"
        return 2
    fi
    if grok_check_image_preference; then
        log INFO "Image preference dialog detected, looking for Skip button..."
        local skip_ref
        skip_ref=$(grok_get_snap_ref 'Skip')
        if [ -n "$skip_ref" ]; then
            log INFO "Skip button found: ref $skip_ref, clicking..."
            grok_click "$skip_ref"
            sleep 2
            return 0
        else
            log WARN "Could not find Skip button in preference dialog"
            return 1
        fi
    fi
    return 2
}

grok_check_video_preference() {
    if [ "$DRY_RUN" = "1" ]; then return 1; fi
    local heading_text
    heading_text=$(grok_eval "(function() { var h = document.evaluate(\"//h3[contains(text(), 'Which video do you prefer to keep?')]\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue; return h ? h.innerText.trim() : ''; })()")
    heading_text=$(echo "$heading_text" | jq -r '.result // empty' 2>/dev/null || echo "$heading_text")
    if echo "$heading_text" | grep -q "Which video do you prefer to keep"; then
        return 0
    fi
    return 1
}

grok_handle_video_preference() {
    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Would check for video preference dialog"
        return 2
    fi
    if grok_check_video_preference; then
        log INFO "Video preference dialog detected, looking for Skip button..."
        local skip_ref
        skip_ref=$(grok_get_snap_ref 'Skip')
        if [ -n "$skip_ref" ]; then
            log INFO "Skip button found: ref $skip_ref, clicking..."
            grok_click "$skip_ref"
            sleep 2
            return 0
        else
            log WARN "Could not find Skip button in preference dialog"
            return 1
        fi
    fi
    return 2
}

usage() {
    cat <<EOF
Usage: $(basename "$0") --project <ID> [options]

Options:
  --project <N>          Project ID (1-4). Required.
  --dry-run              Simulate all actions without executing.
  --log-dir <path>       Directory for log files (default: ./logs/)
  --timeout <seconds>    Global timeout per phase (default: 300)
  --max-retries <N>      Max retries for flaky operations (default: 3)
  --headless             Run BrowserOS in headless mode (if supported)
  --tracker <script>     Override tracker script (auto-detected by project)
  -h, --help             Show this help

Environment Variables:
  BROWSEROS_CLI          Path to browseros-cli binary (default: browseros-cli)
  SELECTOR_INPUT         CSS selector for Grok input area
  SELECTOR_IMAGE         CSS selector for generated image
  SELECTOR_DOWNLOAD      CSS selector for download button
  SELECTOR_MAKE_VIDEO    CSS selector for make video button
  LOG_LEVEL              DEBUG, INFO, WARN, ERROR (default: INFO)
EOF
}

# Phase 1: Preparation
phase_1_preparation() {
    log_section "Phase 1: Preparation"

    if [ -z "$PROJECT_ID" ]; then
        log FATAL "--project is required"
    fi

    validate_project_id "$PROJECT_ID" || log FATAL "Invalid project ID"

    local tracker_script
    tracker_script=$(tracker_resolve_script "$PROJECT_ID")
    log INFO "Using tracker: $tracker_script"

    log INFO "Fetching next pending prompt..."
    local prompt_json
    prompt_json=$(tracker_get_next "$PROJECT_ID")
    log DEBUG "Tracker response: $prompt_json"

    if echo "$prompt_json" | jq -e '.error' >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            log WARN "No pending prompts in dry-run, using dummy prompt for testing"
            PROMPT_ID="dry-run-test"
            PROMPT_TEXT="A simple blue circle on white background, minimal. output 9:16 portrait"
            PROMPT_STATUS="pending"
            return
        fi
        log FATAL "No pending prompts: $(echo "$prompt_json" | jq -r '.error')"
    fi

    PROMPT_ID=$(echo "$prompt_json" | jq -r '.id')
    PROMPT_TEXT=$(echo "$prompt_json" | jq -r '.prompt')
    PROMPT_STATUS=$(echo "$prompt_json" | jq -r '.status // "pending"')

    log INFO "Next prompt ID: $PROMPT_ID"
    log INFO "Status: $PROMPT_STATUS"
    log DEBUG "Prompt: $PROMPT_TEXT"
}

# Phase 2: Platform Navigation
phase_2_navigation() {
    log_section "Phase 2: Platform Navigation"

    log INFO "Opening Grok Imagine page..."
    if ! grok_open_page "https://grok.com/imagine"; then
        log FATAL "Failed to open Grok Imagine page"
    fi
    _dry_run_sleep 2
}

# Phase 3: Image Generation
phase_3_image_generation() {
    log_section "Phase 3: Image Generation"

    log INFO "Finding input area... selector='$SELECTOR_INPUT'"
    local input_info
    input_info=$(grok_find_element "$SELECTOR_INPUT" 30)
    local find_exit=$?
    log DEBUG "phase_3: find_element exit=$find_exit"
    if [ "$find_exit" -eq 2 ]; then
        log FATAL "Browser CDP session lost — restart BrowserOS required"
    elif [ $find_exit -ne 0 ]; then
        log FATAL "Could not find Grok input area"
    fi

    local input_x input_y
    input_x=$(echo "$input_info" | jq -r '.x')
    input_y=$(echo "$input_info" | jq -r '.y')
    log INFO "Input area found at ($input_x, $input_y)"

    log INFO "Typing prompt (length=${#PROMPT_TEXT})..."
    log DEBUG "phase_3: prompt_text='${PROMPT_TEXT:0:80}...'"
    grok_type_text "$PROMPT_TEXT"
    local type_exit=$?
    log DEBUG "phase_3: type_text exit=$type_exit"
    if [ $type_exit -ne 0 ]; then
        log FATAL "Failed to type prompt"
    fi
    _dry_run_sleep 1

    log INFO "Submitting prompt..."
    grok_key "Enter"
    local key_exit=$?
    log DEBUG "phase_3: key Enter exit=$key_exit"
    if [ $key_exit -ne 0 ]; then
        log FATAL "Failed to submit prompt"
    fi

    local poll_interval=5
    local max_wait=120
    local elapsed=0
    local img_ready=0
    log INFO "Waiting for image generation (max_wait=${max_wait}s, poll=${poll_interval}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        log DEBUG "phase_3: polling image gen, elapsed=${elapsed}s"

        if grok_find_element "$SELECTOR_IMAGE" 1 >/dev/null 2>&1; then
            log INFO "Image generated successfully (selector found)"
            img_ready=1
            break
        fi

        if grok_check_image_preference; then
            log INFO "Image preference dialog detected (image generation complete)"
            img_ready=1
            break
        fi

        _dry_run_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        log DEBUG "Elapsed: ${elapsed}s"
    done

    log DEBUG "phase_3: poll loop ended, img_ready=$img_ready elapsed=${elapsed}s"
    if [ "$img_ready" -eq 0 ]; then
        # Check for warning/failure indicators
        local page_text
        page_text=$(grok_text)
        log DEBUG "phase_3: page_text length=${#page_text}"
        if echo "$page_text" | grep -qi "warning"; then
            log WARN "Image generation warning detected"
            local post_url
            post_url=$(grok_get_page_url)
            log DEBUG "phase_3: warning post_url='$post_url'"
            if [ "$PROJECT_ID" != "3" ]; then
                tracker_mark_image_warning "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            else
                tracker_mark_failed "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            fi
            log FATAL "Image generation warning — prompt marked for retry"
        fi
        tracker_mark_image_failed "$PROJECT_ID" "$PROMPT_ID" "$(grok_get_page_url)"
        log FATAL "Timeout waiting for image generation"
    fi
}

# Phase 4: Video Generation
phase_4_video_generation() {
    log_section "Phase 4: Video Generation"

    local elapsed=0
    local max_wait=15
    local handled=0
    log INFO "Checking for image preference dialog (max_wait=${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        log DEBUG "phase_4: polling image preference dialog, elapsed=${elapsed}s"
        local handle_exit
        grok_handle_image_preference
        handle_exit=$?
        log DEBUG "phase_4: handle_image_preference exit=$handle_exit"
        if [ "$handle_exit" -eq 0 ]; then
            log INFO "Image preference dialog handled successfully"
            handled=1
            break
        elif [ "$handle_exit" -eq 1 ]; then
            log WARN "Image preference dialog found but Skip button missing, retrying..."
        fi
        _dry_run_sleep 2
        elapsed=$((elapsed + 2))
    done
    log DEBUG "phase_4: image preference dialog loop ended, handled=$handled elapsed=${elapsed}s"

    if [ "$handled" -eq 0 ]; then
        log INFO "No image preference dialog appeared after ${max_wait}s, continuing..."
    fi

    log INFO "Opening image detail page..."

    log INFO "Clicking generated image to open detail page..."
    local img_info
    img_info=$(grok_find_element "$SELECTOR_IMAGE" 30)
    local img_exit=$?
    log DEBUG "phase_4: find_element SELECTOR_IMAGE exit=$img_exit"
    if [ $img_exit -ne 0 ]; then
        log FATAL "Could not find generated image"
    fi

    local img_x img_y
    img_x=$(echo "$img_info" | jq -r '.x')
    img_y=$(echo "$img_info" | jq -r '.y')

    log INFO "Clicking on generated image at ($img_x, $img_y)..."
    grok_click_at "$img_x" "$img_y"
    _dry_run_sleep 2

    # In Speed mode, clicking the image does not navigate to a detail page.
    # The Make video button is available directly on the results page.
    log INFO "Looking for Make video button... selector='$SELECTOR_MAKE_VIDEO'"
    local mv_info
    mv_info=$(grok_find_element "$SELECTOR_MAKE_VIDEO" 30)
    local mv_exit=$?
    log DEBUG "phase_4: find_element SELECTOR_MAKE_VIDEO exit=$mv_exit"
    if [ $mv_exit -ne 0 ]; then
        log WARN "Make video button not found via selector, trying snap fallback..."
        if ! retry_with_backoff "grok_click_by_snap_pattern 'Make video'" 3 2; then
            log FATAL "Could not find Make video button"
        fi
    else
        # Use snapshot ref click instead of coordinate click.
        # browseros-cli click-at does not reliably trigger the Make video button
        # in Speed mode where multiple images are shown on the results page.
        log INFO "Make video button found via selector, using snapshot ref click..."
        if ! grok_click_by_snap_pattern 'Make video'; then
            log FATAL "Could not click Make video button via snapshot ref"
        fi
    fi
    log INFO "Video generation triggered"
    _dry_run_sleep 3
}

# Phase 5: Monitoring & Validation
phase_5_monitoring() {
    log_section "Phase 5: Monitoring & Validation"

    local poll_interval=10
    local max_wait=150
    local elapsed=0
    local video_ready=0

    log INFO "Polling for video completion (max ${max_wait}s, interval=${poll_interval}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        log DEBUG "phase_5: poll iteration elapsed=${elapsed}s"

        local page_text
        page_text=$(grok_text)
        log DEBUG "phase_5: page_text lines=$(echo "$page_text" | wc -l | tr -d ' ')"

        local snapshot_text
        snapshot_text=$(grok_snap)
        log DEBUG "phase_5: snapshot lines=$(echo "$snapshot_text" | wc -l | tr -d ' ')"

        if grok_check_video_preference; then
            log INFO "Video preference dialog detected (video generation complete)"
            video_ready=1
            break
        fi

        if echo "$snapshot_text" | grep -q "Redo video"; then
            log INFO "Video ready (Redo video button detected)"
            video_ready=1
            break
        fi

        if echo "$snapshot_text" | grep "Download" | grep -qv "(disabled)"; then
            log INFO "Video ready (Download button enabled)"
            video_ready=1
            break
        fi

        if echo "$page_text" | grep -qi "generating"; then
            local pct
            pct=$(echo "$page_text" | grep -oE '[0-9]+%' | head -1)
            if [ -n "$pct" ]; then
                log INFO "Still generating... $pct"
            else
                log INFO "Still generating..."
            fi
        fi

        # Speed mode: percentage shown as clickable elements (e.g., "4%")
        local snap_pct
        snap_pct=$(echo "$snapshot_text" | grep -oE '^\[[0-9]+\][[:space:]]+clickable[[:space:]]+"[0-9]+%"' | head -1)
        if [ -n "$snap_pct" ]; then
            log INFO "Video generation in progress (Speed mode: $snap_pct)"
        fi

        # Speed mode: Save button changing to Unsave indicates processing started
        if echo "$snapshot_text" | grep -q '"Unsave"'; then
            log DEBUG "phase_5: Unsave button detected (video processing active)"
        fi

        if echo "$snapshot_text" | grep -qi "warning"; then
            log WARN "Video generation warning detected"
            local post_url
            post_url=$(grok_get_page_url)
            log DEBUG "phase_5: warning post_url='$post_url'"
            tracker_mark_video_warning "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            log FATAL "Video generation warning — prompt marked for retry"
        fi

        _dry_run_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        log DEBUG "Elapsed: ${elapsed}s"
    done

    log DEBUG "phase_5: poll loop ended, video_ready=$video_ready elapsed=${elapsed}s"
    if [ "$video_ready" -eq 0 ]; then
        local post_url
        post_url=$(grok_get_page_url)
        log DEBUG "phase_5: timeout post_url='$post_url'"
        tracker_mark_video_failed "$PROJECT_ID" "$PROMPT_ID" "$post_url"
        log FATAL "Timeout waiting for video generation"
    fi
}

# Phase 6: Asset Management
phase_6_asset_management() {
    log_section "Phase 6: Asset Management"

    log INFO "Checking for video preference dialog..."
    local video_handle_exit
    grok_handle_video_preference
    video_handle_exit=$?
    log DEBUG "phase_6: handle_video_preference exit=$video_handle_exit"
    if [ "$video_handle_exit" -eq 1 ]; then
        log WARN "Failed to handle video preference dialog (Skip button not found), continuing anyway..."
    elif [ "$video_handle_exit" -eq 0 ]; then
        log INFO "Video preference dialog handled successfully"
    else
        log DEBUG "phase_6: no video preference dialog present"
    fi

    log INFO "Waiting 5 seconds for file stabilization..."
    _dry_run_sleep 5

    log INFO "Taking snapshot to find Download button..."
    local dl_ref=""
    local retries=0
    local max_dl_retries=3
    while [ "$retries" -lt "$max_dl_retries" ]; do
        log DEBUG "phase_6: find Download attempt=$retries"
        dl_ref=$(grok_get_snap_ref 'Download')
        log DEBUG "phase_6: dl_ref='$dl_ref'"
        if [ -n "$dl_ref" ]; then
            break
        fi
        log WARN "Download button not found in snapshot, retrying..."
        _dry_run_sleep 2
        retries=$((retries + 1))
    done

    if [ -z "$dl_ref" ]; then
        log FATAL "Download button not found in snapshot after $max_dl_retries retries"
    fi
    log INFO "Download button found: ref $dl_ref"

    local dest_dir="$REPO_ROOT/project-$PROJECT_ID/assets/current"
    mkdir -p "$dest_dir"
    log INFO "Destination: $dest_dir"

    log INFO "Downloading via browseros-cli (ref: $dl_ref)..."
    local download_output
    local download_exit=0
    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Would download ref $dl_ref to $dest_dir"
        touch "$dest_dir/dry-run-video.mp4"
        download_output="Downloaded \"dry-run-video.mp4\" to $dest_dir/dry-run-video.mp4"
    else
        download_output=$(grok_download "$dl_ref" "$dest_dir" 2>&1)
        download_exit=$?
    fi
    log DEBUG "phase_6: download_exit=$download_output"
    log DEBUG "phase_6: download output: $download_output"

    if [ "$download_exit" -ne 0 ]; then
        log FATAL "Download failed (exit $download_exit)"
    fi

    local downloaded_file
    downloaded_file=$(echo "$download_output" | sed -n 's/.*Downloaded "\([^"]*\)".*/\1/p')
    log DEBUG "phase_6: downloaded_file from regex='$downloaded_file'"
    if [ -z "$downloaded_file" ]; then
        downloaded_file=$(ls -t "$dest_dir"/*.mp4 2>/dev/null | head -1)
        downloaded_file=$(basename "$downloaded_file" 2>/dev/null)
        log DEBUG "phase_6: downloaded_file from ls='$downloaded_file'"
    fi

    if [ -z "$downloaded_file" ]; then
        log FATAL "Could not determine downloaded file name"
    fi

    log INFO "Downloaded file: $downloaded_file"

    local final_name="${PROMPT_ID}.mp4"
    local src_path="$dest_dir/$downloaded_file"
    local dst_path="$dest_dir/$final_name"

    if [ "$src_path" != "$dst_path" ]; then
        mv "$src_path" "$dst_path"
        log INFO "Renamed to: $final_name"
    fi

    FINAL_PATH="$dst_path"
    log INFO "Asset saved: $FINAL_PATH"

    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Skipping file validation"
    else
        if ! validate_file "$FINAL_PATH" 1024; then
            log FATAL "Downloaded file is missing or too small"
        fi
        local fsize
        fsize=$(stat -f%z "$FINAL_PATH" 2>/dev/null || stat -c%s "$FINAL_PATH" 2>/dev/null)
        log INFO "File validated: $fsize bytes"
    fi
}

# Phase 7: Recording & Tracking
phase_7_recording() {
    log_section "Phase 7: Recording & Tracking"

    log INFO "Getting page URL..."
    local post_url
    post_url=$(grok_get_page_url)
    log INFO "Post URL: $post_url"

    log INFO "Getting video URL..."
    local video_url
    video_url=$(grok_eval "document.querySelector('video')?.src || window.location.href")
    video_url=$(echo "$video_url" | jq -r '.result // empty' 2>/dev/null)
    log DEBUG "phase_7: video_url from eval='$video_url'"
    if [ -z "$video_url" ]; then
        video_url="$post_url"
        log DEBUG "phase_7: falling back to post_url"
    fi
    log INFO "Video URL: $video_url"

    log INFO "Updating tracker... project=$PROJECT_ID prompt=$PROMPT_ID"
    local tracker_result
    tracker_result=$(tracker_complete "$PROJECT_ID" "$PROMPT_ID" "$video_url" "$post_url")
    log DEBUG "phase_7: tracker_result='$tracker_result'"

    if echo "$tracker_result" | jq -e '.success' >/dev/null 2>&1; then
        log INFO "Prompt $PROMPT_ID marked complete"
    else
        log ERROR "Tracker update failed: $(echo "$tracker_result" | jq -r '.error')"
    fi
}

main() {
    framework_setup "$@"

    phase_1_preparation
    phase_2_navigation
    phase_3_image_generation
    phase_4_video_generation
    phase_5_monitoring
    phase_6_asset_management
    phase_7_recording

    log_section "Complete"
    log INFO "Successfully processed prompt $PROMPT_ID"
    log INFO "Asset: $FINAL_PATH"
    log INFO "Log file: $LOG_FILE"
    log DEBUG "main: finished"
}

main "$@"
