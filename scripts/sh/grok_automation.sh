#!/usr/bin/env bash
# grok_automation.sh — Main Grok home automation script
# Converts .agents/workflows/grok_home_automation.md into a deterministic shell script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/tracker.sh"
source "$SCRIPT_DIR/lib/browser.sh"

# Defaults
PROJECT_ID=""
DRY_RUN=0
LOG_DIR="$REPO_ROOT/logs"
TIMEOUT=300
MAX_RETRIES=3
HEADLESS=0

_dry_run_sleep() {
    if [ "$DRY_RUN" = "1" ]; then
        sleep 0
    else
        sleep "$1"
    fi
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

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --headless)
                HEADLESS=1
                shift
                ;;
            --tracker)
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
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

    log INFO "Checking BrowserOS health..."
    if ! retry_with_backoff "bos_health" "$MAX_RETRIES" 5; then
        log FATAL "BrowserOS not reachable. Run: browseros-cli init --auto && browseros-cli launch"
    fi
    log INFO "BrowserOS is healthy"

    log INFO "Navigating to Grok Imagine..."
    bos_navigate "https://grok.com/imagine"
    _dry_run_sleep 2
}

# Phase 3: Image Generation
phase_3_image_generation() {
    log_section "Phase 3: Image Generation"

    log INFO "Finding input area..."
    local input_info
    input_info=$(bos_find_element "$SELECTOR_INPUT" 30)
    if [ $? -ne 0 ]; then
        log FATAL "Could not find Grok input area"
    fi

    local input_x input_y
    input_x=$(echo "$input_info" | jq -r '.x')
    input_y=$(echo "$input_info" | jq -r '.y')
    log INFO "Input area found at ($input_x, $input_y)"

    log INFO "Typing prompt..."
    bos_type_text "$PROMPT_TEXT"
    if [ $? -ne 0 ]; then
        log FATAL "Failed to type prompt"
    fi
    _dry_run_sleep 1

    log INFO "Submitting prompt..."
    bos_key "Enter"
    if [ $? -ne 0 ]; then
        log FATAL "Failed to submit prompt"
    fi

    log INFO "Waiting for image generation..."
    if ! bos_wait_for "bos_find_element \"\$SELECTOR_IMAGE\" 1 >/dev/null" 5 120; then
        # Check for warning/failure indicators
        local page_text
        page_text=$(bos_text)
        if echo "$page_text" | grep -qi "warning"; then
            log WARN "Image generation warning detected"
            local post_url
            post_url=$(bos_get_page_url)
            if [ "$PROJECT_ID" != "3" ]; then
                tracker_mark_image_warning "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            else
                tracker_mark_failed "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            fi
            log FATAL "Image generation warning — prompt marked for retry"
        fi
        tracker_mark_image_failed "$PROJECT_ID" "$PROMPT_ID" "$(bos_get_page_url)"
        log FATAL "Timeout waiting for image generation"
    fi
    log INFO "Images generated successfully"
}

# Phase 4: Video Generation
phase_4_video_generation() {
    log_section "Phase 4: Video Generation"

    log INFO "Opening image detail page..."

    # Primary Method: Use snapshot to find and click the first link element
    log INFO "Trying snapshot method to find first image link..."
    if retry_with_backoff "bos_click_first_link" 3 2; then
        log INFO "Clicked first link from snapshot"
        _dry_run_sleep 2
    else
        # Fallback Method: Click the generated image coordinates
        log WARN "Snapshot link method failed, falling back to image coordinates..."
        local img_info
        img_info=$(bos_find_element "$SELECTOR_IMAGE" 30)
        if [ $? -ne 0 ]; then
            log FATAL "Could not find generated image"
        fi

        local img_x img_y
        img_x=$(echo "$img_info" | jq -r '.x')
        img_y=$(echo "$img_info" | jq -r '.y')

        log INFO "Clicking on generated image at ($img_x, $img_y)..."
        bos_click_at "$img_x" "$img_y"
        _dry_run_sleep 2
    fi

    log INFO "Looking for Make video button..."
    local mv_info
    mv_info=$(bos_find_element "$SELECTOR_MAKE_VIDEO" 30)
    if [ $? -ne 0 ]; then
        log WARN "Make video button not found via selector, trying snap fallback..."
        if ! retry_with_backoff "bos_click_by_snap_pattern 'Make video'" 3 2; then
            log FATAL "Could not find Make video button"
        fi
    else
        local mv_x mv_y
        mv_x=$(echo "$mv_info" | jq -r '.x')
        mv_y=$(echo "$mv_info" | jq -r '.y')
        bos_click_at "$mv_x" "$mv_y"
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

    log INFO "Polling for video completion (max ${max_wait}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        local page_text
        page_text=$(bos_text)

        local snapshot_text
        snapshot_text=$(bos_snap)

        if echo "$snapshot_text" | grep -q "Redo video"; then
            log INFO "Video ready (Redo video button detected)"
            break
        fi

        if echo "$snapshot_text" | grep "Download" | grep -qv "(disabled)"; then
            log INFO "Video ready (Download button enabled)"
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

        if echo "$snapshot_text" | grep -qi "warning"; then
            log WARN "Video generation warning detected"
            local post_url
            post_url=$(bos_get_page_url)
            tracker_mark_video_warning "$PROJECT_ID" "$PROMPT_ID" "$post_url"
            log FATAL "Video generation warning — prompt marked for retry"
        fi

        _dry_run_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        log DEBUG "Elapsed: ${elapsed}s"
    done

    if [ "$elapsed" -ge "$max_wait" ]; then
        local post_url
        post_url=$(bos_get_page_url)
        tracker_mark_video_failed "$PROJECT_ID" "$PROMPT_ID" "$post_url"
        log FATAL "Timeout waiting for video generation"
    fi
}

# Phase 6: Asset Management
phase_6_asset_management() {
    log_section "Phase 6: Asset Management"

    log INFO "Waiting 5 seconds for file stabilization..."
    _dry_run_sleep 5

    log INFO "Finding Download button..."
    local dl_info
    dl_info=$(bos_find_element "$SELECTOR_DOWNLOAD" 30)
    local dl_ref=""
    local dl_x=""
    local dl_y=""

    if [ $? -eq 0 ]; then
        dl_x=$(echo "$dl_info" | jq -r '.x // empty')
        dl_y=$(echo "$dl_info" | jq -r '.y // empty')
    fi

    # Fallback: try snap pattern
    if [ -z "$dl_x" ]; then
        log WARN "Download button not found via selector, trying snap fallback..."
        dl_ref=$(bos_get_snap_ref 'Download')
        if [ -z "$dl_ref" ]; then
            log FATAL "Download button not found"
        fi
    fi

    local dest_dir="$REPO_ROOT/project-$PROJECT_ID/assets/current"
    mkdir -p "$dest_dir"
    log INFO "Destination: $dest_dir"

    local download_exit=0
    if [ -n "$dl_ref" ]; then
        log INFO "Downloading via browseros-cli (ref: $dl_ref)..."
        download_with_curl_fallback "$dl_ref" "$dest_dir"
        download_exit=$?
    else
        log INFO "Clicking download at ($dl_x, $dl_y)..."
        bos_click_at "$dl_x" "$dl_y"
        sleep 5
    fi

    if [ "$download_exit" -ne 0 ]; then
        log FATAL "Download failed"
    fi

    log INFO "Running downloader process..."
    local downloader_result
    downloader_result=$(downloader_process "$PROJECT_ID" "$dest_dir" "$PROMPT_ID")
    log DEBUG "Downloader result: $downloader_result"

    if ! echo "$downloader_result" | jq -e '.success' >/dev/null 2>&1; then
        log FATAL "Downloader failed: $(echo "$downloader_result" | jq -r '.error')"
    fi

    FINAL_PATH=$(echo "$downloader_result" | jq -r '.path')
    log INFO "Asset saved: $FINAL_PATH"

    if ! validate_file "$FINAL_PATH" 1024; then
        log FATAL "Downloaded file is missing or too small"
    fi
    log INFO "File validated: $(stat -f%z "$FINAL_PATH" 2>/dev/null || stat -c%s "$FINAL_PATH" 2>/dev/null) bytes"
}

# Phase 7: Recording & Tracking
phase_7_recording() {
    log_section "Phase 7: Recording & Tracking"

    log INFO "Getting page URL..."
    local post_url
    post_url=$(bos_get_page_url)
    log INFO "Post URL: $post_url"

    log INFO "Getting video URL..."
    local video_url
    video_url=$(bos_eval "document.querySelector('video')?.src || window.location.href")
    video_url=$(echo "$video_url" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$video_url" ]; then
        video_url="$post_url"
    fi
    log INFO "Video URL: $video_url"

    log INFO "Updating tracker..."
    local tracker_result
    tracker_result=$(tracker_complete "$PROJECT_ID" "$PROMPT_ID" "$video_url" "$post_url")
    log DEBUG "Tracker result: $tracker_result"

    if echo "$tracker_result" | jq -e '.success' >/dev/null 2>&1; then
        log INFO "Prompt $PROMPT_ID marked complete"
    else
        log ERROR "Tracker update failed: $(echo "$tracker_result" | jq -r '.error')"
    fi
}

main() {
    parse_args "$@"

    # Export for libraries
    export DRY_RUN
    export MAX_RETRIES

    log_init "$LOG_DIR"

    if [ "$DRY_RUN" = "1" ]; then
        log INFO "=== DRY RUN MODE ==="
        log INFO "No actual browser commands will be executed"
    fi

    log INFO "Starting Grok automation for project $PROJECT_ID"
    log INFO "Timeout: ${TIMEOUT}s, Max retries: $MAX_RETRIES"

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
}

main "$@"
