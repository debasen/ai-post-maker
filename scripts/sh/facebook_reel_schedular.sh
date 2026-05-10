#!/usr/bin/env bash
# facebook_reel_schedular.sh — Facebook Reels scheduling automation
# Reuses the upload flow from facebook_upload.sh, but schedules posts instead of manual publishing.

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
  --schedule-file <path> Path to schedule JSON (default: auto-generate)
  --log-dir <path>       Directory for log files (default: ./logs/)
  --timeout <seconds>    Global timeout per phase (default: 300)
  --max-retries <N>      Max retries for flaky operations (default: 3)
  --pause                Pause after each post for manual review
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
        schedule_path="$REPO_ROOT/project-$PROJECT_ID/schedule.json"
        if [ -f "$schedule_path" ]; then
            log INFO "Existing schedule found: $schedule_path"
        else
            log INFO "Generating new schedule..."
            python3 "$REPO_ROOT/scripts/generate_reel_schedule.py" > "$schedule_path"
            log INFO "Schedule saved to: $schedule_path"
        fi
    fi

    # Read schedule entries into array
    local json_content
    json_content=$(cat "$schedule_path")
    local entry_count
    entry_count=$(echo "$json_content" | jq 'length')

    if [ "$entry_count" -eq 0 ]; then
        log FATAL "Schedule is empty"
    fi

    log INFO "Schedule entries: $entry_count"

    # Store entries in a global temp file for indexed access
    SCHEDULE_TEMP="$(mktemp)"
    echo "$json_content" | jq -c '.[]' > "$SCHEDULE_TEMP"
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

# ─── Phase 9: Open Scheduling Options ──────────────────────────────────────────

phase_9_open_scheduling() {
    log_section "Phase 9: Open Scheduling Options"

    # Find scheduling trigger via snapshot
    local sched_ref
    sched_ref=$(fb_get_snap_ref 'button "Scheduling options"')
    if [ -z "$sched_ref" ]; then
        sched_ref=$(fb_get_snap_ref 'div "Scheduling options"')
    fi
    if [ -z "$sched_ref" ]; then
        # Fallback: look via JS for any button containing "Scheduling"
        sched_ref=$(fb_eval_result "(function() { var btns = Array.from(document.querySelectorAll('div[role=\"button\"], button')); for (var i = 0; i < btns.length; i++) { var b = btns[i]; var txt = b.innerText || b.textContent || ''; if (txt.toLowerCase().includes('scheduling options')) return i; } return ''; })()")
    fi

    if [ -z "$sched_ref" ]; then
        log WARN "Could not find 'Scheduling options' trigger via snapshot or JS"
        local snap_debug
        snap_debug=$(fb_snap)
        log_save_artifact "phase9_snapshot" "$snap_debug"
        log FATAL "Could not find 'Scheduling options' trigger (snapshot saved to log dir)"
    fi

    log INFO "Clicking scheduling trigger (ref: $sched_ref)..."
    fb_click "$sched_ref"
    sleep 3

    # Verify popup opened - look for date picker or "Schedule for later" button
    local popup_check
    popup_check=$(fb_eval_result "!!document.querySelector('button[aria-label*=\"Date Picker\"]') || !!document.querySelector('button[aria-label*=\"Time Picker\"]')")
    if [ "$popup_check" != "true" ]; then
        # Try broader check
        popup_check=$(fb_eval_result "document.body.innerText.includes('Schedule for later')")
    fi
    if [ "$popup_check" != "true" ]; then
        log WARN "Scheduling popup not immediately detected, waiting..."
        sleep 3
        popup_check=$(fb_eval_result "document.body.innerText.includes('Schedule for later')")
    fi
    if [ "$popup_check" != "true" ]; then
        log FATAL "Scheduling popup not detected"
    fi

    log INFO "Scheduling popup confirmed"
}

# ─── Phase 10: Fill Date and Time ──────────────────────────────────────────────

phase_10_fill_datetime() {
    log_section "Phase 10: Fill Date and Time"

    # Parse current schedule entry
    # SCHEDULE_DATE, SCHEDULE_DAY, SCHEDULE_TIME are set by get_schedule_entry

    # Format date for Facebook UI: "11 May 2026"
    local fb_date
    fb_date=$(python3 -c "from datetime import datetime; print(datetime.strptime('$SCHEDULE_DATE', '%Y-%m-%d').strftime('%d %B %Y'))")

    # Format time: HH:MM (strip seconds)
    local fb_time
    fb_time="${SCHEDULE_TIME%:*}"  # e.g., 09:29

    log INFO "Setting date: $fb_date, time: $fb_time"

    # ── Date: click the date picker button, then use JS to select the date ──
    local date_ref
    date_ref=$(fb_get_snap_ref 'button "Open Date Picker"')
    if [ -n "$date_ref" ]; then
        log INFO "Clicking date picker (ref: $date_ref)..."
        fb_click "$date_ref"
        sleep 2
    fi

    # Use JS to find and click the correct date cell
    local date_set
    date_set=$(fb_eval_result "(function() {
        var target = '$fb_date';
        var cells = document.querySelectorAll('[role=\"dialog\"] [role=\"gridcell\"], [role=\"dialog\"] td, [role=\"dialog\"] [class*=\"calendar\"] *');
        for (var i = 0; i < cells.length; i++) {
            var txt = cells[i].getAttribute('aria-label') || cells[i].innerText || '';
            if (txt.trim() === target || txt.includes(target)) {
                cells[i].click();
                return 'clicked: ' + txt;
            }
        }
        // Fallback: try to find any clickable containing the date
        var all = document.querySelectorAll('[role=\"dialog\"] *');
        for (var i = 0; i < all.length; i++) {
            var txt = all[i].getAttribute('aria-label') || '';
            if (txt.includes(target)) {
                all[i].click();
                return 'clicked fallback: ' + txt;
            }
        }
        return 'date not found in calendar';
    })()")
    log DEBUG "Date selection result: $date_set"
    sleep 1

    # ── Time: use JS to find the input and set value directly ──
    local time_set
    time_set=$(fb_eval_result "(function() {
        var timeValue = '$fb_time';
        // Find input near 'Time' label
        var timeLabel = Array.from(document.querySelectorAll('*')).find(function(e) {
            return (e.innerText || '').trim() === 'Time';
        });
        if (timeLabel) {
            var parent = timeLabel.parentElement;
            var input = parent.querySelector('input, select');
            if (input) {
                input.value = timeValue;
                input.dispatchEvent(new Event('input', {bubbles: true}));
                input.dispatchEvent(new Event('change', {bubbles: true}));
                return 'set time to ' + timeValue;
            }
        }
        // Fallback: search by aria-label
        var inputs = document.querySelectorAll('input, select');
        for (var i = 0; i < inputs.length; i++) {
            var label = (inputs[i].getAttribute('aria-label') || '').toLowerCase();
            if (label.includes('time')) {
                inputs[i].value = timeValue;
                inputs[i].dispatchEvent(new Event('change', {bubbles: true}));
                return 'set time via aria-label to ' + timeValue;
            }
        }
        return 'time input not found';
    })()")
    log DEBUG "Time selection result: $time_set"
    sleep 1

    log INFO "Date and time filled"
}

# ─── Phase 11: Click Schedule ──────────────────────────────────────────────────

phase_11_click_schedule() {
    log_section "Phase 11: Click Schedule"

    local sched_btn_ref
    sched_btn_ref=$(fb_get_snap_ref 'button "Schedule for later"')
    if [ -z "$sched_btn_ref" ]; then
        sched_btn_ref=$(fb_get_snap_ref 'div "Schedule for later"')
    fi
    if [ -z "$sched_btn_ref" ]; then
        # Try via JS
        sched_btn_ref=$(fb_eval_result "(function() { var btns = Array.from(document.querySelectorAll('div[role=\"button\"], button')); for (var i = 0; i < btns.length; i++) { var b = btns[i]; var txt = b.innerText || b.textContent || ''; if (txt.trim() === 'Schedule for later') return i; } return ''; })()")
    fi

    if [ -z "$sched_btn_ref" ]; then
        log WARN "Could not find 'Schedule for later' button via snapshot or JS"
        local snap_debug
        snap_debug=$(fb_snap)
        log_save_artifact "phase11_snapshot" "$snap_debug"
        log FATAL "Could not find 'Schedule for later' button (snapshot saved to log dir)"
    fi

    log INFO "Clicking 'Schedule for later' button (ref: $sched_btn_ref)..."
    fb_click "$sched_btn_ref"
    sleep 5

    # Verify – look for success indicator
    local verify
    verify=$(fb_eval_result "document.body.innerText.includes('Scheduled') || document.body.innerText.includes('Your reel is scheduled') || document.body.innerText.includes('successfully scheduled') || document.body.innerText.includes('Your post is scheduled')")
    log INFO "Schedule verification: $verify"

    if [ "$verify" != "true" ]; then
        log WARN "Could not confirm scheduling success via text check"
    fi
}

# ─── Phase 12: User Verification ───────────────────────────────────────────────

phase_12_user_confirm() {
    log_section "Phase 12: User Verification"

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

    if [ "$DRY_RUN" = "1" ]; then
        log INFO "[DRY-RUN] Auto-confirming tracker update"
        confirm="y"
    else
        read -r -p "Reel scheduled for $SCHEDULE_DATE $SCHEDULE_TIME. Confirm? [y/N]: " confirm
    fi
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log WARN "User did not confirm. Skipping tracker update."
        return 1
    fi

    # Update tracker
    log INFO "Marking asset $ASSET_ID as uploaded for facebook..."
    local tracker_output
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_uploaded "$ASSET_ID" facebook 2>&1)
    local tracker_exit=$?
    log DEBUG "mark_uploaded output: $tracker_output"
    if [ $tracker_exit -ne 0 ]; then
        log ERROR "mark_uploaded failed: $tracker_output"
    fi

    log INFO "Marking asset $ASSET_ID as scheduled for facebook..."
    local schedule_json
    schedule_json=$(printf '%s' "{\"date\":\"$SCHEDULE_DATE\",\"day\":\"$SCHEDULE_DAY\",\"time\":\"$SCHEDULE_TIME\"}")
    tracker_output=$(python3 "$REPO_ROOT/scripts/py/grok_tracker.py" --project "$PROJECT_ID" mark_scheduled "$ASSET_ID" facebook "$schedule_json" 2>&1)
    tracker_exit=$?
    log DEBUG "mark_scheduled output: $tracker_output"
    if [ $tracker_exit -ne 0 ]; then
        log ERROR "mark_scheduled failed: $tracker_output"
    fi

    log INFO "Tracker updated for asset $ASSET_ID"
}

# ─── Phase 13: Close Browser Tab ───────────────────────────────────────────────

phase_13_close_tab() {
    log_section "Phase 13: Close Browser Tab"

    fb_close_page
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
        phase_2_read_url
        phase_3_open_page
        phase_4_open_dialog
        phase_5_upload_video
        phase_6_navigate_caption
        phase_7_enter_caption
        phase_8_final_review
        phase_9_open_scheduling
        phase_10_fill_datetime
        phase_11_click_schedule
        phase_12_user_confirm
        phase_13_close_tab

        current_idx=$((current_idx + 1))

        if [ "$PAUSE" -eq 1 ] && [ "$current_idx" -lt "$total_entries" ] && [ "$DRY_RUN" != "1" ]; then
            log INFO "Pause enabled. Press Enter to continue to next entry..."
            read -r
        fi
    done

    rm -f "$SCHEDULE_TEMP"

    log_section "Complete"
    log INFO "Facebook reel scheduling finished for project-$PROJECT_ID"
    log INFO "Processed $current_idx / $total_entries entries"
    log INFO "Log file: $LOG_FILE"
}

main "$@"
