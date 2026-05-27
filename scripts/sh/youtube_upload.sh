#!/usr/bin/env bash
# youtube_upload.sh — YouTube Shorts upload automation
# Modeled after facebook_upload.sh for consistent execution

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source Framework
source "$SCRIPT_DIR/lib/framework.sh"

# ─── Page-aware BrowserOS helpers ──────────────────────────────────────────────

BROWSEROS_CLI="${BROWSEROS_CLI:-browseros-cli}"
PAGE_ID=""

_yt_bos() {
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

yt_open_page() {
    local url="$1"
    log INFO "Opening new page: $url"
    local output
    output=$(_yt_bos open "$url" --json)
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

yt_snap() {
    _yt_bos snap -p "$PAGE_ID"
}

yt_eval() {
    local js="$1"
    local output
    output=$(_yt_bos eval -p "$PAGE_ID" "$js")
    local eval_exit=$?
    if [ $eval_exit -ne 0 ]; then
        log ERROR "yt_eval failed"
        return 1
    fi
    echo "$output"
}

yt_eval_result() {
    local js="$1"
    local output
    output=$(yt_eval "$js")
    echo "$output" | jq -r 'if type == "object" then .result // empty else . end' 2>/dev/null
}

yt_click() {
    local ref="$1"
    _yt_bos click -p "$PAGE_ID" "$ref"
}

yt_fill() {
    local ref="$1"
    local text="$2"
    _yt_bos fill -p "$PAGE_ID" "$ref" "$text"
}

yt_upload() {
    local ref="$1"
    local file="$2"
    _yt_bos upload -p "$PAGE_ID" "$ref" "$file"
}

yt_text() {
    _yt_bos text -p "$PAGE_ID"
}

yt_close_page() {
    _yt_bos close -p "$PAGE_ID"
}

yt_get_snap_ref() {
    local pattern="$1"
    local snapshot_text
    snapshot_text=$(yt_snap)
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
  --yolo                 Automatically click Publish without manual review
  -h, --help             Show this help

Environment Variables:
  BROWSEROS_CLI          Path to browseros-cli binary (default: browseros-cli)
  LOG_LEVEL              DEBUG, INFO, WARN, ERROR (default: INFO)
EOF
}

# Override framework_parse_args to add --yolo
framework_parse_args() {
    YOLO=0
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
            --yolo)
                YOLO=1
                shift
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
    mapped_output=$(python3 "$REPO_ROOT/scripts/py/get_mapped_post.py" --project "$PROJECT_ID" --platform youtube 2>&1)
    local mapped_exit=$?
    log DEBUG "get_mapped_post exit=$mapped_exit output='$mapped_output'"

    if [ $mapped_exit -ne 0 ]; then
        log FATAL "get_mapped_post.py failed: $mapped_output"
    fi

    ASSET_ID=$(echo "$mapped_output" | awk '/^ID:/{print substr($0, index($0,$2))}')
    local FULL_CAPTION
    FULL_CAPTION=$(echo "$mapped_output" | awk 'BEGIN{found=0} /^Caption:/{found=1; sub(/^Caption:[[:space:]]*/, ""); print; next} found && /^ID:/{exit} found{print}')

    if [ -z "$ASSET_ID" ]; then
        log FATAL "No mapped asset found for project $PROJECT_ID"
    fi
    if [ -z "$FULL_CAPTION" ]; then
        log FATAL "No caption found for mapped asset"
    fi

    # Split Caption into Title (first line, max 100 chars) and Description
    TITLE=$(echo "$FULL_CAPTION" | head -1 | cut -c 1-100)
    DESCRIPTION=$(echo "$FULL_CAPTION" | tail -n +2)

    log INFO "Asset ID: $ASSET_ID"
    log INFO "Title length: ${#TITLE} chars"
    log INFO "Description length: ${#DESCRIPTION} chars"

    ASSET_PATH="$REPO_ROOT/project-$PROJECT_ID/assets/$ASSET_ID.mp4"
    log INFO "Asset path: $ASSET_PATH"

    if [ ! -f "$ASSET_PATH" ]; then
        log FATAL "Asset file not found: $ASSET_PATH"
    fi
}

# ─── Phase 2: Open YouTube Upload Page ─────────────────────────────────────────

phase_2_open_page() {
    log_section "Phase 2: Open YouTube Upload Page"

    YT_URL="https://www.youtube.com/upload"
    yt_open_page "$YT_URL"
    sleep 5

    log INFO "Page loaded successfully"
}

# ─── Phase 3: Upload the Video File ────────────────────────────────────────────

phase_3_upload_video() {
    log_section "Phase 3: Upload the Video File"

    log INFO "Exposing hidden file input..."
    yt_eval "document.querySelectorAll('input[type=\"file\"]').forEach((i, idx) => { i.removeAttribute('aria-hidden'); i.style.display='block'; i.style.visibility='visible'; i.style.opacity='1'; i.style.position='static'; i.style.width='100px'; i.style.height='50px'; i.style.zIndex='999999'; i.title='Upload Video File'; });" > /dev/null
    sleep 2

    log INFO "Taking snapshot to find file input..."
    local file_input_ref
    file_input_ref=$(yt_get_snap_ref 'button "Upload Video File"')
    if [ -z "$file_input_ref" ]; then
        file_input_ref=$(yt_get_snap_ref 'Upload Video File')
    fi
    if [ -z "$file_input_ref" ]; then
        file_input_ref=$(yt_get_snap_ref 'Choose Files')
    fi
    if [ -z "$file_input_ref" ]; then
        file_input_ref=$(yt_get_snap_ref 'Choose File')
    fi
    if [ -z "$file_input_ref" ]; then
        file_input_ref=$(yt_get_snap_ref 'Select files')
    fi
    if [ -z "$file_input_ref" ]; then
        log FATAL "Could not find file input in snapshot"
    fi

    log INFO "Attempting upload to ref: $file_input_ref..."
    if ! yt_upload "$file_input_ref" "$ASSET_PATH" > /dev/null 2>&1; then
        log FATAL "Upload failed"
    fi
    sleep 5

    log INFO "Waiting for 'Details' screen to appear..."
    local attempt=1
    local max_attempts=12
    local ready=0

    while [ "$attempt" -le "$max_attempts" ]; do
        local check_result
        check_result=$(yt_snap)
        
        if echo "$check_result" | grep -iq "Add a title"; then
            ready=1
            break
        fi
        log INFO "Waiting... (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done

    if [ "$ready" -eq 0 ]; then
        log FATAL "Details screen did not appear after upload"
    fi

    log INFO "Video uploaded and Details screen reached"
}

# ─── Phase 4: Fill Details (Title, Description, Kids) ──────────────────────────

phase_4_fill_details() {
    log_section "Phase 4: Fill Details"

    log INFO "Finding Title field..."
    local title_ref
    title_ref=$(yt_get_snap_ref 'textbox "Add a title')
    if [ -z "$title_ref" ]; then
        log FATAL "Could not find Title field in snapshot"
    fi
    log INFO "Filling Title..."
    yt_fill "$title_ref" "$TITLE"
    sleep 2

    log INFO "Finding Description field..."
    local desc_ref
    desc_ref=$(yt_get_snap_ref 'textbox "Tell viewers about your video')
    if [ -z "$desc_ref" ]; then
        log WARN "Could not find Description field in snapshot. Will try generic 'Tell viewers' match."
        desc_ref=$(yt_get_snap_ref 'Tell viewers')
    fi
    if [ -n "$desc_ref" ]; then
        log INFO "Filling Description..."
        yt_fill "$desc_ref" "$DESCRIPTION"
    else
        log WARN "Skipping description - field not found"
    fi
    sleep 2

    log INFO "Selecting 'Not made for kids'..."
    local kids_ref
    kids_ref=$(yt_get_snap_ref 'radio "No, it.s not made for kids"')
    if [ -z "$kids_ref" ]; then
        kids_ref=$(yt_get_snap_ref 'No, it.s not made for kids')
    fi
    if [ -n "$kids_ref" ]; then
        yt_click "$kids_ref"
        log INFO "Selected 'Not made for kids'"
    else
        log WARN "Could not find 'Not made for kids' radio button. It might be already selected by default."
    fi
    sleep 2
}

# ─── Phase 5: Navigate to Visibility Screen ────────────────────────────────────

phase_5_navigate_visibility() {
    log_section "Phase 5: Navigate to Visibility Screen"

    local max_clicks=3
    local click_num=1

    while [ "$click_num" -le "$max_clicks" ]; do
        local next_ref
        next_ref=$(yt_get_snap_ref 'button "Next"')
        if [ -z "$next_ref" ]; then
            log FATAL "Could not find 'Next' button (click $click_num)"
        fi

        log INFO "Clicking Next ($click_num/$max_clicks)..."
        yt_click "$next_ref"
        sleep 3
        
        local text_check
        text_check=$(yt_snap)
        if echo "$text_check" | grep -iq 'Visibility" (selected'; then
            log INFO "Reached Visibility screen"
            break
        fi
        click_num=$((click_num + 1))
    done
}

# ─── Phase 6: Select Public ────────────────────────────────────────────────────

phase_6_select_public() {
    log_section "Phase 6: Select Public Visibility"

    log INFO "Selecting 'Public' radio button..."
    local public_ref
    public_ref=$(yt_get_snap_ref 'radio "Public"')
    if [ -z "$public_ref" ]; then
        public_ref=$(yt_get_snap_ref 'Public')
    fi
    
    if [ -n "$public_ref" ]; then
        yt_click "$public_ref"
        sleep 2
    else
        log FATAL "Could not find 'Public' radio button"
    fi
}

# ─── Phase 7: Manual Review / Publish ──────────────────────────────────────────

phase_7_review_publish() {
    log_section "Phase 7: Manual Review / Publish"

    if [ "${YOLO:-0}" = "1" ]; then
        log INFO "[YOLO] Auto-publishing..."
        local publish_ref
        publish_ref=$(yt_get_snap_ref 'button "Publish"')
        if [ -z "$publish_ref" ]; then
            publish_ref=$(yt_get_snap_ref 'button "Save"')
        fi
        
        if [ -n "$publish_ref" ]; then
            yt_click "$publish_ref"
            log INFO "Clicked Publish/Save"
            sleep 10
        else
            log FATAL "Could not find Publish/Save button"
        fi
    else
        log INFO ""
        log INFO "============================================"
        log INFO "  MANUAL REVIEW REQUIRED"
        log INFO "============================================"
        log INFO "  Asset ID: $ASSET_ID"
        log INFO "  Project:  project-$PROJECT_ID"
        log INFO "  Status:   Ready to publish"
        log INFO ""
        log INFO "  Please review the video in the browser."
        log INFO "  DO NOT proceed until you manually click"
        log INFO "  the 'Publish' button and confirm success."
        log INFO "============================================"
        log INFO ""

        read -r -p "Have you successfully published the video? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log WARN "User did not confirm publication. Skipping tracker update."
            exit 1
        fi
    fi
}

# ─── Phase 8: Mark Record as Done ──────────────────────────────────────────────

phase_8_mark_done() {
    log_section "Phase 8: Mark Record as Done"

    log INFO "Marking asset $ASSET_ID as uploaded for youtube..."
    local tracker_output
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_uploaded "$ASSET_ID" youtube 2>&1)
    local tracker_exit=$?
    log DEBUG "Tracker output: $tracker_output"

    if [ $tracker_exit -ne 0 ]; then
        log FATAL "Tracker update failed: $tracker_output"
    fi

    log INFO "Record $ASSET_ID marked as uploaded for youtube in project-$PROJECT_ID/grok_prompts.json"
}

# ─── Phase 9: Close Browser Tab ────────────────────────────────────────────────

phase_9_close_tab() {
    log_section "Phase 9: Close Browser Tab"

    yt_close_page
    log INFO "Browser tab closed"
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    framework_setup "$@"

    phase_1_identify_asset
    phase_2_open_page
    phase_3_upload_video
    phase_4_fill_details
    phase_5_navigate_visibility
    phase_6_select_public
    phase_7_review_publish
    phase_8_mark_done
    phase_9_close_tab

    log_section "Complete"
    log INFO "YouTube upload workflow finished for project-$PROJECT_ID"
    log INFO "Log file: $LOG_FILE"
}

main "$@"
