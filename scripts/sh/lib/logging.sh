#!/usr/bin/env bash
# lib/logging.sh — Logging utilities for Grok automation

set -uo pipefail

LOG_LEVEL=${LOG_LEVEL:-INFO}
LOG_LEVELS=(DEBUG INFO WARN ERROR FATAL)
LOG_FILE=""
LOG_DIR=""

log_level_to_int() {
    local lvl="$1"
    case "$lvl" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        FATAL) echo 4 ;;
        *)     echo 1 ;;
    esac
}

# Example of the new log initialization in lib/logging.sh
log_init() {
    local dir="${1:-./logs}"
    LOG_DIR="$dir"
    mkdir -p "$LOG_DIR"
    local script_name
    script_name=$(basename "$0" .sh)
    LOG_FILE="$LOG_DIR/${script_name}.log"
    # Truncate existing log file to "override" instead of creating new ones
    : > "$LOG_FILE"
    log INFO "Logging initialized: $LOG_FILE"
}


log() {
    local level="$1"
    local message="$2"
    local current
    local target
    current=$(log_level_to_int "$LOG_LEVEL")
    target=$(log_level_to_int "$level")
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts] [$level] $message"
    if [ "$target" -ge "$current" ]; then
        echo "$line" >&2
    fi
    if [ -n "$LOG_FILE" ]; then
        echo "$line" >> "$LOG_FILE"
    fi
    if [ "$level" = "FATAL" ]; then
        exit 1
    fi
}

log_cmd() {
    local cmd="$1"
    local output="$2"
    local exit_code="$3"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local truncated_output
    truncated_output=$(echo "$output" | tail -n 50)
    {
        echo ""
        echo "[$ts] [CMD] $cmd"
        echo "[$ts] [EXIT] $exit_code"
        echo "[$ts] [OUT] ---"
        echo "$truncated_output"
        echo "[$ts] [OUT] ---"
    } >> "$LOG_FILE"
    if [ "$exit_code" -ne 0 ]; then
        log WARN "Command failed (exit $exit_code): $cmd"
    fi
}

log_section() {
    local title="$1"
    local sep="========================================"
    log INFO "$sep"
    log INFO "  $title"
    log INFO "$sep"
}

log_save_artifact() {
    local name="$1"
    local content="$2"
    if [ -z "$LOG_DIR" ]; then
        return
    fi
    local path="$LOG_DIR/artifact_$(date +%Y%m%d_%H%M%S)_${name}"
    echo "$content" > "$path"
    log DEBUG "Artifact saved: $path"
}
