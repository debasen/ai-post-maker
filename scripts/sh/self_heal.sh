#!/usr/bin/env bash
# self_heal.sh — Self-healing agent for grok_automation failures
# Analyzes recent logs, detects failures, and attempts recovery actions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/browser.sh"

# Config
LOG_FILE="${REPO_ROOT}/logs/grok_automation.log"
STATE_DIR="${REPO_ROOT}/.self_heal"
STATE_FILE="$STATE_DIR/last_check"
LOCK_FILE="$STATE_DIR/lock"
REPORT_FILE="$STATE_DIR/report.txt"
HEAL_LOG="$STATE_DIR/heal.log"
CHECK_WINDOW_MINUTES="${CHECK_WINDOW_MINUTES:-70}"
MAX_HEAL_ATTEMPTS="${MAX_HEAL_ATTEMPTS:-3}"
KILO_BIN="${KILO_BIN:-kilo}"

# Ensure state dir exists
mkdir -p "$STATE_DIR"

# Redirect all stdout/stderr to heal log for traceability
exec >> "$HEAL_LOG"
exec 2>&1

log_init "$STATE_DIR"

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log INFO "Self-heal already running (PID $lock_pid). Exiting."
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Determine "since" timestamp for log analysis
if [ -f "$STATE_FILE" ]; then
    SINCE_EPOCH=$(cat "$STATE_FILE")
else
    SINCE_EPOCH=$(date -v-${CHECK_WINDOW_MINUTES}M +%s 2>/dev/null || date -d "-${CHECK_WINDOW_MINUTES} minutes" +%s)
fi

log INFO "========================================"
log INFO "Self-heal check started (since epoch: $SINCE_EPOCH)"
log INFO "========================================"

# --- Helper: extract recent errors from log ---
extract_recent_errors() {
    local since_epoch="$1"
    local log_path="$2"
    if [ ! -f "$log_path" ]; then
        log WARN "Log file not found: $log_path"
        return 1
    fi
    awk -v since="$since_epoch" '
        # Parse timestamp like [2026-05-09 23:30:00]
        match($0, /^\[([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2})\] \[(ERROR|FATAL|WARN)\] (.*)/, m) {
            ts = m[1] " " m[2]
            # Convert to epoch (requires GNU date or BSD date)
            cmd = "date -j -f \"%Y-%m-%d %H:%M:%S\" \"" ts "\" +%s 2>/dev/null || date -d \"" ts "\" +%s"
            cmd | getline epoch
            close(cmd)
            if (epoch + 0 >= since + 0) {
                print m[3] " | " m[4]
            }
        }
    ' "$log_path" 2>/dev/null
}

# Fallback parser using grep + simple filtering if awk fails
extract_recent_errors_fallback() {
    local since_epoch="$1"
    local log_path="$2"
    local since_human
    since_human=$(date -r "$since_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$since_epoch" '+%Y-%m-%d %H:%M:%S')
    grep -E '^\[.*\] \[(ERROR|FATAL|WARN)\]' "$log_path" | while IFS= read -r line; do
        ts=$(echo "$line" | sed -n 's/^\[\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)\].*/\1/p')
        if [ -z "$ts" ]; then continue; fi
        epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$ts" +%s 2>/dev/null || date -d "$ts" +%s 2>/dev/null)
        if [ -n "$epoch" ] && [ "$epoch" -ge "$since_epoch" ]; then
            level=$(echo "$line" | sed -n 's/^\[.*\] \[\([A-Z]*\)\].*/\1/p')
            msg=$(echo "$line" | sed -n 's/^\[.*\] \[[A-Z]*\] //p')
            echo "$level | $msg"
        fi
    done
}

ERRORS=$(extract_recent_errors "$SINCE_EPOCH" "$LOG_FILE" 2>/dev/null)
if [ -z "$ERRORS" ]; then
    ERRORS=$(extract_recent_errors_fallback "$SINCE_EPOCH" "$LOG_FILE" 2>/dev/null)
fi

# --- Helper: classify errors and decide actions ---
classify_errors() {
    local errors="$1"
    local actions=""
    local needs_browser_restart=0
    local needs_selector_fix=0
    local needs_kilo_analysis=0
    local needs_timeout_bump=0

    while IFS= read -r line; do
        case "$line" in
            *"CDP session lost"*|*"Session with given id not found"*|*"CDP error"*)
                needs_browser_restart=1
                ;;
            *"Could not find"*|*"not found"*|*"Element not found"*)
                needs_selector_fix=1
                needs_kilo_analysis=1
                ;;
            *"Timeout"*|*"timeout"*)
                needs_timeout_bump=1
                ;;
            *"FATAL"*)
                needs_kilo_analysis=1
                ;;
        esac
    done <<< "$errors"

    if [ "$needs_browser_restart" -eq 1 ]; then
        actions="${actions}restart_browser,"
    fi
    if [ "$needs_selector_fix" -eq 1 ]; then
        actions="${actions}fix_selectors,"
    fi
    if [ "$needs_timeout_bump" -eq 1 ]; then
        actions="${actions}bump_timeouts,"
    fi
    if [ "$needs_kilo_analysis" -eq 1 ]; then
        actions="${actions}kilo_analysis,"
    fi

    echo "$actions"
}

# --- Recovery actions ---
action_restart_browser() {
    log INFO "[ACTION] Restarting BrowserOS..."
    # Try graceful restart via CLI
    if command -v "$BROWSEROS_CLI" >/dev/null 2>&1; then
        "$BROWSEROS_CLI" close --all 2>/dev/null || true
        sleep 2
        "$BROWSEROS_CLI" launch 2>/dev/null || true
        sleep 5
    fi
    # Also try killing any stale browser processes as last resort
    if pgrep -f "browseros" >/dev/null 2>&1; then
        log WARN "Killing stale browseros processes..."
        pkill -f "browseros" 2>/dev/null || true
        sleep 3
    fi
    if command -v "$BROWSEROS_CLI" >/dev/null 2>&1; then
        "$BROWSEROS_CLI" launch 2>/dev/null || true
        sleep 5
    fi
    if bos_health; then
        log INFO "[ACTION] BrowserOS restart successful"
        return 0
    else
        log ERROR "[ACTION] BrowserOS restart FAILED"
        return 1
    fi
}

action_bump_timeouts() {
    log INFO "[ACTION] Bumping timeouts in framework..."
    local framework="$SCRIPT_DIR/lib/framework.sh"
    if [ -f "$framework" ]; then
        sed -i.bak 's/^TIMEOUT=.*/TIMEOUT=600/' "$framework" 2>/dev/null || \
            sed -i '' 's/^TIMEOUT=.*/TIMEOUT=600/' "$framework" 2>/dev/null || true
        sed -i.bak 's/^MAX_RETRIES=.*/MAX_RETRIES=5/' "$framework" 2>/dev/null || \
            sed -i '' 's/^MAX_RETRIES=.*/MAX_RETRIES=5/' "$framework" 2>/dev/null || true
        log INFO "[ACTION] TIMEOUT bumped to 600s, MAX_RETRIES to 5"
    fi
}

action_kilo_analysis() {
    log INFO "[ACTION] Invoking kilo for deep log analysis..."
    local errors="$1"
    local prompt
    prompt=$(cat <<EOF
Analyze these recent grok_automation errors and suggest a fix.
The codebase is in scripts/sh/grok_automation.sh, scripts/sh/lib/browser.sh, and scripts/sh/lib/framework.sh.
Recent errors:
$errors
EOF
)
    # Run kilo non-interactively with the prompt
    if command -v "$KILO_BIN" >/dev/null 2>&1; then
        "$KILO_BIN" run "$prompt" 2>&1 | tee "$REPORT_FILE"
        log INFO "[ACTION] Kilo report saved to $REPORT_FILE"
    else
        log WARN "[ACTION] kilo CLI not found, skipping AI analysis"
    fi
}

action_fix_selectors() {
    log INFO "[ACTION] Attempting selector refresh via kilo..."
    local prompt
    prompt=$(cat <<EOF
The Grok UI may have changed. Review scripts/sh/lib/browser.sh selectors and update them if needed based on common Grok Imagine page patterns.
Current selectors:
SELECTOR_INPUT="$SELECTOR_INPUT"
SELECTOR_IMAGE="$SELECTOR_IMAGE"
SELECTOR_DOWNLOAD="$SELECTOR_DOWNLOAD"
SELECTOR_MAKE_VIDEO="$SELECTOR_MAKE_VIDEO"
EOF
)
    if command -v "$KILO_BIN" >/dev/null 2>&1; then
        "$KILO_BIN" run "$prompt" 2>&1 | tee -a "$REPORT_FILE"
        log INFO "[ACTION] Selector fix report appended to $REPORT_FILE"
    fi
}

# --- Main flow ---
CURRENT_EPOCH=$(date +%s)
echo "$CURRENT_EPOCH" > "$STATE_FILE"

if [ -z "$ERRORS" ]; then
    log INFO "No recent errors found in the last ${CHECK_WINDOW_MINUTES} minutes. Nothing to heal."
    exit 0
fi

ERROR_COUNT=$(echo "$ERRORS" | grep -c '^' || echo "0")
log INFO "Detected $ERROR_COUNT recent error(s):"
echo "$ERRORS" | while IFS= read -r e; do log INFO "  - $e"; done

ACTIONS=$(classify_errors "$ERRORS")
log INFO "Planned actions: $ACTIONS"

HEAL_COUNT=0
if echo "$ACTIONS" | grep -q "restart_browser"; then
    action_restart_browser
    HEAL_COUNT=$((HEAL_COUNT + 1))
fi

if echo "$ACTIONS" | grep -q "bump_timeouts"; then
    action_bump_timeouts
    HEAL_COUNT=$((HEAL_COUNT + 1))
fi

if echo "$ACTIONS" | grep -q "kilo_analysis"; then
    action_kilo_analysis "$ERRORS"
    HEAL_COUNT=$((HEAL_COUNT + 1))
fi

if echo "$ACTIONS" | grep -q "fix_selectors"; then
    action_fix_selectors
    HEAL_COUNT=$((HEAL_COUNT + 1))
fi

log INFO "========================================"
log INFO "Self-heal check complete. Actions taken: $HEAL_COUNT"
log INFO "State saved: $STATE_FILE"
log INFO "Report: $REPORT_FILE"
log INFO "========================================"
