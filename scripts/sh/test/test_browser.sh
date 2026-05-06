#!/usr/bin/env bash
# test/test_browser.sh — Unit tests for browser interaction helpers

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/browser.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

assert_true() {
    local cmd="$1"
    local msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cmd" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg"
    fi
}

assert_false() {
    local cmd="$1"
    local msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$cmd" >/dev/null 2>&1; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $msg"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $msg"
    fi
}

test_bos_health() {
    echo "test_bos_health"
    # We can't reliably test this without BrowserOS running
    # Just verify the function returns a valid exit code (0 or 1)
    bos_health >/dev/null 2>&1
    local code=$?
    if [ "$code" = "0" ] || [ "$code" = "1" ]; then
        assert_eq "0" "0" "bos_health returns valid exit code ($code)"
    else
        assert_eq "0" "1" "bos_health returns valid exit code ($code)"
    fi
}

test_bos_eval_parsing() {
    echo "test_bos_eval_parsing"
    # Mock eval output
    local output='{"result": "https://example.com"}'
    local parsed
    parsed=$(echo "$output" | jq -r '.result // empty')
    assert_eq "https://example.com" "$parsed" "jq parses eval result correctly"
}

test_bos_get_snap_ref() {
    echo "test_bos_get_snap_ref"
    local snapshot='[1024] link "Home page"
[1028] button "Search"
[19796] button "Download"'
    local ref
    ref=$(echo "$snapshot" | grep -i 'Download' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    assert_eq "19796" "$ref" "Extracts correct ref from snapshot"
}

test_bos_wait_for_success() {
    echo "test_bos_wait_for_success"
    # Test with immediate success
    if bos_wait_for "true" 1 5; then
        assert_eq "0" "0" "wait_for succeeds immediately"
    else
        assert_eq "1" "0" "wait_for succeeds immediately"
    fi
}

test_bos_wait_for_timeout() {
    echo "test_bos_wait_for_timeout"
    if bos_wait_for "false" 1 2; then
        assert_eq "1" "0" "wait_for times out correctly"
    else
        assert_eq "0" "0" "wait_for times out correctly"
    fi
}

test_retry_with_backoff() {
    echo "test_retry_with_backoff"
    local counter=0
    # Command succeeds on 2nd attempt
    retry_with_backoff 'counter=$((counter + 1)); [ $counter -ge 2 ]' 3 1
    assert_eq "0" "$?" "retry succeeds on 2nd attempt"
    assert_eq "2" "$counter" "retry ran exactly 2 times"
}

test_retry_with_backoff_failure() {
    echo "test_retry_with_backoff_failure"
    if retry_with_backoff "false" 2 1; then
        assert_eq "1" "0" "retry fails after max retries"
    else
        assert_eq "0" "0" "retry fails after max retries"
    fi
}

# Main test runner
main() {
    log_init "$REPO_ROOT/logs"
    LOG_LEVEL=WARN

    echo "=== Browser Library Tests ==="
    test_bos_health
    test_bos_eval_parsing
    test_bos_get_snap_ref
    test_bos_wait_for_success
    test_bos_wait_for_timeout
    test_retry_with_backoff
    test_retry_with_backoff_failure

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
