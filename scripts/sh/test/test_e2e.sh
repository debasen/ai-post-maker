#!/usr/bin/env bash
# test/test_e2e.sh — End-to-end dry-run test

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg"
        echo "    expected to contain: $needle"
    fi
}

test_dry_run_parsing() {
    echo "test_dry_run_parsing"
    local output
    output=$("$REPO_ROOT/scripts/sh/grok_automation.sh" --dry-run --project 1 2>&1)
    assert_contains "$output" "DRY RUN MODE" "Shows dry run banner"
    assert_contains "$output" "Phase 1: Preparation" "Enters Phase 1"
    assert_contains "$output" "Phase 2: Platform Navigation" "Enters Phase 2"
    assert_contains "$output" "Phase 3: Image Generation" "Enters Phase 3"
    assert_contains "$output" "Phase 4: Video Generation" "Enters Phase 4"
    assert_contains "$output" "Phase 5: Monitoring" "Enters Phase 5"
    assert_contains "$output" "Phase 6: Asset Management" "Enters Phase 6"
    assert_contains "$output" "Phase 7: Recording" "Enters Phase 7"
}

test_help_output() {
    echo "test_help_output"
    local output
    output=$("$REPO_ROOT/scripts/sh/grok_automation.sh" --help 2>&1)
    assert_contains "$output" "--project" "Help mentions --project"
    assert_contains "$output" "--dry-run" "Help mentions --dry-run"
}

test_invalid_project() {
    echo "test_invalid_project"
    local output
    output=$("$REPO_ROOT/scripts/sh/grok_automation.sh" --project 99 2>&1 || true)
    assert_contains "$output" "Invalid project ID" "Rejects invalid project"
}

test_log_file_created() {
    echo "test_log_file_created"
    local log_dir="$(mktemp -d)"
    local output
    output=$("$REPO_ROOT/scripts/sh/grok_automation.sh" --dry-run --project 1 --log-dir "$log_dir" 2>&1)
    local log_files
    log_files=$(find "$log_dir" -name "grok_automation_*.log" 2>/dev/null)
    if [ -n "$log_files" ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: Log file created"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: Log file not created"
    fi
    rm -rf "$log_dir"
}

main() {
    echo "=== E2E Dry-Run Tests ==="
    test_dry_run_parsing
    test_help_output
    test_invalid_project
    test_log_file_created

    echo ""
    echo "=== Results ==="
    echo "Run:    $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
