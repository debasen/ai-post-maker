#!/usr/bin/env bash
# lib/framework.sh — Browser OS Automation Framework

set -uo pipefail

# Find script directory and repo root based on the calling script
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source libraries
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/tracker.sh"
source "$SCRIPT_DIR/lib/browser.sh"

# Framework Defaults
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
            -h|--help)
                if type usage >/dev/null 2>&1; then
                    usage
                else
                    echo "Usage: $(basename "$0") --project <ID> [options]"
                fi
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                if type usage >/dev/null 2>&1; then
                    usage
                fi
                exit 1
                ;;
        esac
    done
}

framework_init_browseros() {
    log INFO "Checking BrowserOS health..."
    if ! bos_health; then
        log INFO "BrowserOS not reachable, attempting to launch..."
        if ! _bos launch; then
            log FATAL "BrowserOS not reachable. Run: browseros-cli init --auto && browseros-cli launch"
        fi
        # Wait a bit for server to stabilize even after launch says it's ready
        sleep 5
    fi
    
    if ! retry_with_backoff "bos_health" "$MAX_RETRIES" 5; then
        log FATAL "BrowserOS not reachable after launch attempt."
    fi
    log INFO "BrowserOS is healthy"
}

framework_setup() {
    framework_parse_args "$@"

    # Export for libraries
    export DRY_RUN
    export MAX_RETRIES

    log_init "$LOG_DIR"

    if [ "$DRY_RUN" = "1" ]; then
        log INFO "=== DRY RUN MODE ==="
        log INFO "No actual browser commands will be executed"
    fi

    log INFO "Starting automation for project ${PROJECT_ID:-unknown}"
    log INFO "Timeout: ${TIMEOUT}s, Max retries: $MAX_RETRIES"

    framework_init_browseros
}
