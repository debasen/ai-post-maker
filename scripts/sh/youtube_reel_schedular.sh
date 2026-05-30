#!/usr/bin/env bash
# youtube_reel_schedular.sh — YouTube Shorts scheduling automation
# Reuses the upload flow from youtube_upload.sh, but schedules posts instead of manual publishing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source Framework
source "$SCRIPT_DIR/lib/framework.sh"

# ─── Script-specific options ───────────────────────────────────────────────────

SCHEDULE_FILE=""
PAUSE=0
CURRENT_ENTRY_INDEX=0
SCHEDULE_ENTRIES=()
SCHEDULE_DATE=""
SCHEDULE_DAY=""
SCHEDULE_TIME=""
YOLO=0

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

yt_key() {
    local key="$1"
    _yt_bos key -p "$PAGE_ID" "$key"
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
  --schedule-file <path> Path to schedule JSON (default: project-<N>/youtube_schedule.json)
  --log-dir <path>       Directory for log files (default: ./logs/)
  --timeout <seconds>    Global timeout per phase (default: 300)
  --max-retries <N>      Max retries for flaky operations (default: 3)
  --pause                Pause after each post for manual review
  --yolo                 Automatically click Schedule and skip user confirmation
  --dry-run              Simulate without executing browser commands
  -h, --help             Show this help

Environment Variables:
  BROWSEROS_CLI          Path to browseros-cli binary (default: browseros-cli)
  LOG_LEVEL              DEBUG, INFO, WARN, ERROR (default: INFO)
EOF
}

# Override framework_parse_args to add --schedule-file and --pause
framework_parse_args() {
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
            --schedule-file)
                SCHEDULE_FILE="$2"
                shift 2
                ;;
            --pause)
                PAUSE=1
                shift
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

# ─── Schedule Management ───────────────────────────────────────────────────────

load_or_generate_schedule() {
    log_section "Schedule Management"

    local schedule_path
    if [ -n "$SCHEDULE_FILE" ]; then
        schedule_path="$SCHEDULE_FILE"
        if [ ! -f "$schedule_path" ]; then
            log FATAL "Schedule file not found: $schedule_path"
        fi
        log INFO "Loading schedule from: $schedule_path"
    else
        schedule_path="$REPO_ROOT/project-$PROJECT_ID/youtube_schedule.json"
        if [ ! -f "$schedule_path" ]; then
            log INFO "Generating youtube_schedule for project-$PROJECT_ID..."
            python3 "$REPO_ROOT/scripts/generate_reel_schedule.py" --project "$PROJECT_ID" --platform youtube
        fi
        log INFO "Schedule path: $schedule_path"
    fi

    # Read schedule entries, normalize status fields
    local json_content
    json_content=$(cat "$schedule_path")

    # Normalize: add status="pending" if missing
    json_content=$(echo "$json_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for entry in data:
    if 'status' not in entry:
        entry['status'] = 'pending'
json.dump(data, sys.stdout, indent=2)
")

    # Save normalized version back
    echo "$json_content" > "$schedule_path"

    # Filter to unscheduled entries only
    local unscheduled
    unscheduled=$(echo "$json_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
unscheduled = [e for e in data if e.get('status') != 'scheduled']
json.dump(unscheduled, sys.stdout, indent=2)
")

    local entry_count
    entry_count=$(echo "$unscheduled" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

    if [ "$entry_count" -eq 0 ]; then
        log FATAL "No unscheduled entries in schedule"
    fi

    log INFO "Unscheduled entries: $entry_count"

    # Store unscheduled entries in a global temp file for indexed access
    SCHEDULE_TEMP="$(mktemp)"
    echo "$unscheduled" | jq -c '.[]' > "$SCHEDULE_TEMP"
}

get_schedule_entry() {
    local idx="$1"
    local line
    line=$(sed -n "$((idx + 1))p" "$SCHEDULE_TEMP")
    if [ -z "$line" ]; then
        return 1
    fi
    SCHEDULE_DATE=$(echo "$line" | jq -r '.date')
    SCHEDULE_DAY=$(echo "$line" | jq -r '.day')
    SCHEDULE_TIME=$(echo "$line" | jq -r '.time')
    return 0
}

mark_schedule_entry_done() {
    local date="$1"
    local time="$2"

    local schedule_path
    if [ -n "$SCHEDULE_FILE" ]; then
        schedule_path="$SCHEDULE_FILE"
    else
        schedule_path="$REPO_ROOT/project-$PROJECT_ID/youtube_schedule.json"
    fi

    if [ ! -f "$schedule_path" ]; then
        log WARN "Schedule file not found for marking done: $schedule_path"
        return 1
    fi

    python3 -c "
import json
path = '$schedule_path'
date = '$date'
time = '$time'

with open(path, 'r') as f:
    data = json.load(f)

marked = False
for entry in data:
    if entry.get('date') == date and entry.get('time') == time and entry.get('status') != 'scheduled':
        entry['status'] = 'scheduled'
        marked = True
        break

if marked:
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print('marked')
else:
    print('not_found')
" > /dev/null
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

# ─── Phase 6: Select Schedule ──────────────────────────────────────────────────

phase_6_select_schedule() {
    log_section "Phase 6: Open Scheduling Options"

    log INFO "Clicking 'Schedule' option..."
    local sched_ref
    sched_ref=$(yt_get_snap_ref 'clickable "Schedule')
    if [ -z "$sched_ref" ]; then
        sched_ref=$(yt_get_snap_ref 'Schedule')
    fi

    if [ -n "$sched_ref" ]; then
        yt_click "$sched_ref"
        sleep 2
    else
        log FATAL "Could not find 'Schedule' clickable"
    fi
}

# ─── Phase 7: Fill Date and Time ───────────────────────────────────────────────

phase_7_fill_datetime() {
    log_section "Phase 7: Fill Date and Time"

    # In YouTube UI, the date picker needs to be opened to reveal the input box
    # Format the date (e.g. 2026-05-27 -> May 27, 2026)
    local sched_year="${SCHEDULE_DATE:0:4}"
    local sched_month_num="${SCHEDULE_DATE:5:2}"
    local sched_day="${SCHEDULE_DATE:8:2}"
    local sched_month=""
    case "$sched_month_num" in
        01) sched_month="Jan" ;;
        02) sched_month="Feb" ;;
        03) sched_month="Mar" ;;
        04) sched_month="Apr" ;;
        05) sched_month="May" ;;
        06) sched_month="Jun" ;;
        07) sched_month="Jul" ;;
        08) sched_month="Aug" ;;
        09) sched_month="Sep" ;;
        10) sched_month="Oct" ;;
        11) sched_month="Nov" ;;
        12) sched_month="Dec" ;;
    esac

    local yt_day_normalized="${sched_day#0}"
    local yt_date_target="$sched_month $yt_day_normalized, $sched_year"
    
    # Standardize time format for YouTube (e.g. 15:00 -> 3:00 PM)
    local hour_24="${SCHEDULE_TIME:0:2}"
    local min="${SCHEDULE_TIME:3:2}"
    local hour_12="$hour_24"
    local am_pm="AM"
    if [ "$hour_24" -ge 12 ]; then
        am_pm="PM"
        if [ "$hour_24" -gt 12 ]; then
            hour_12=$((hour_24 - 12))
        fi
    elif [ "$hour_24" -eq 0 ]; then
        hour_12=12
    fi
    # Remove leading 0 from hour if present
    hour_12=$((10#$hour_12))
    local yt_time_target="$hour_12:$min $am_pm"

    log INFO "Setting date: $yt_date_target, time: $yt_time_target"

    # -- Date selection --
    log INFO "Opening date picker..."
    local snapshot_text
    snapshot_text=$(yt_snap)
    local date_picker_btn_ref
    # Find a button that looks like a date to click it
    date_picker_btn_ref=$(echo "$snapshot_text" | grep -i 'button ".* 202[0-9]"' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$date_picker_btn_ref" ]; then
        yt_click "$date_picker_btn_ref"
        sleep 2
    else
        log FATAL "Could not find date picker button to click"
    fi

    # Now the calendar is open, find the date textbox and fill it
    snapshot_text=$(yt_snap)
    local date_textbox_ref
    date_textbox_ref=$(echo "$snapshot_text" | grep -E 'textbox value=".* 202[0-9]"' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$date_textbox_ref" ]; then
        yt_fill "$date_textbox_ref" "$yt_date_target"
        sleep 1
        yt_key "Enter"
        sleep 2
    else
        log FATAL "Could not find date textbox to fill"
    fi

    # -- Time selection --
    log INFO "Setting time..."
    snapshot_text=$(yt_snap)
    local time_textbox_ref
    time_textbox_ref=$(echo "$snapshot_text" | grep -E 'textbox value=".*(AM|PM|am|pm)"' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -z "$time_textbox_ref" ]; then
        time_textbox_ref=$(echo "$snapshot_text" | grep -i '12:00.*AM' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    fi
    
    if [ -n "$time_textbox_ref" ]; then
        log INFO "Clicking time input box to open dropdown..."
        yt_click "$time_textbox_ref"
        sleep 2
        
        snapshot_text=$(yt_snap)
        local opt_pattern="option \"$hour_12:$min.*$am_pm\""
        local option_ref
        option_ref=$(echo "$snapshot_text" | grep -i "$opt_pattern" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
        if [ -z "$option_ref" ]; then
            option_ref=$(echo "$snapshot_text" | grep -i "$hour_12:$min.*$am_pm" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
        fi
        
        if [ -n "$option_ref" ]; then
            log INFO "Clicking time option ref: $option_ref for $yt_time_target"
            yt_click "$option_ref"
            sleep 2
        else
            log FATAL "Could not find time option in dropdown matching: $hour_12:$min $am_pm"
        fi
    else
        log FATAL "Could not find time textbox to click"
    fi

    log INFO "Date and time filled successfully"
}

# ─── Phase 8: User Verification ────────────────────────────────────────────────

phase_8_user_confirm() {
    log_section "Phase 8: User Verification"

    log INFO ""
    log INFO "============================================"
    log INFO "  SCHEDULED REEL REVIEW"
    log INFO "============================================"
    log INFO "  Asset ID: $ASSET_ID"
    log INFO "  Project:  project-$PROJECT_ID"
    log INFO "  Date:     $SCHEDULE_DATE ($SCHEDULE_DAY)"
    log INFO "  Time:     $SCHEDULE_TIME"
    log INFO "============================================"
    log INFO ""

    local confirm="n"
    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Auto-confirming tracker update"
        confirm="y"
    elif [ "$YOLO" = "1" ]; then
        log INFO "[YOLO] Finding 'Schedule' button..."
        local schedule_button_ref
        schedule_button_ref=$(yt_get_snap_ref 'button "Schedule"')

        if [ -n "$schedule_button_ref" ]; then
            log INFO "Clicking 'Schedule' button (ref: $schedule_button_ref)..."
            yt_click "$schedule_button_ref"
            sleep 10
            confirm="y"
        else
            log ERROR "Could not find 'Schedule' button in snapshot"
            confirm="n"
        fi
    else
        read -r -p "Reel scheduled for $SCHEDULE_DATE $SCHEDULE_TIME. Confirm? [y/N]: " confirm
    fi
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log WARN "Verification did not succeed or user did not confirm. Skipping tracker update."
        return 1
    fi

    # Update tracker
    log INFO "Marking asset $ASSET_ID as uploaded for youtube..."
    local tracker_output
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_uploaded "$ASSET_ID" youtube 2>&1)
    local tracker_exit=$?
    log DEBUG "mark_uploaded output: $tracker_output"
    if [ $tracker_exit -ne 0 ]; then
        log ERROR "mark_uploaded failed: $tracker_output"
    fi

    log INFO "Marking asset $ASSET_ID as scheduled for youtube..."
    local schedule_json
    schedule_json=$(printf '%s' "{\"date\":\"$SCHEDULE_DATE\",\"day\":\"$SCHEDULE_DAY\",\"time\":\"$SCHEDULE_TIME\"}")
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_scheduled "$ASSET_ID" youtube "$schedule_json" 2>&1)
    tracker_exit=$?
    log DEBUG "mark_scheduled output: $tracker_output"
    if [ $tracker_exit -ne 0 ]; then
        log ERROR "mark_scheduled failed: $tracker_output"
    fi

    log INFO "Tracker updated for asset $ASSET_ID"
}

# ─── Phase 9: Close Browser Tab ────────────────────────────────────────────────

phase_9_close_tab() {
    log_section "Phase 9: Close Browser Tab"

    yt_close_page
    log INFO "Browser tab closed"
}

# ─── Main Loop ─────────────────────────────────────────────────────────────────

main() {
    framework_setup "$@"

    load_or_generate_schedule

    local total_entries
    total_entries=$(wc -l < "$SCHEDULE_TEMP" | tr -d ' ')
    log INFO "Total schedule entries to process: $total_entries"

    local current_idx=0
    while get_schedule_entry "$current_idx"; do
        CURRENT_ENTRY_INDEX=$current_idx
        log_section "Processing Schedule Entry $((current_idx + 1)) / $total_entries"
        log INFO "Date: $SCHEDULE_DATE, Day: $SCHEDULE_DAY, Time: $SCHEDULE_TIME"

        phase_1_identify_asset
        phase_2_open_page
        phase_3_upload_video
        phase_4_fill_details
        phase_5_navigate_visibility
        phase_6_select_schedule
        phase_7_fill_datetime
        phase_8_user_confirm
        local confirm_exit=$?
        phase_9_close_tab

        if [ $confirm_exit -ne 0 ]; then
            log WARN "User did not confirm entry $((current_idx + 1)). Stopping scheduler."
            break
        fi
        mark_schedule_entry_done "$SCHEDULE_DATE" "$SCHEDULE_TIME"

        current_idx=$((current_idx + 1))

        if [ "$PAUSE" -eq 1 ] && [ "$current_idx" -lt "$total_entries" ] && [ "$DRY_RUN" != "1" ]; then
            log INFO "Pause enabled. Press Enter to continue to next entry..."
            read -r
        fi
    done

    rm -f "$SCHEDULE_TEMP"

    log_section "Complete"
    log INFO "YouTube reel scheduling finished for project-$PROJECT_ID"
    log INFO "Processed $current_idx / $total_entries entries"
    log INFO "Log file: $LOG_FILE"
}

main "$@"
