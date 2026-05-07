#!/usr/bin/env bash
# lib/browser.sh — browseros-cli wrappers with retry logic

# lib/browser.sh — browseros-cli wrappers with retry logic
if ! command -v "${BROWSEROS_CLI:-browseros-cli}" >/dev/null 2>&1; then
    if [ -f "/opt/homebrew/bin/browseros-cli" ]; then
        export BROWSEROS_CLI="/opt/homebrew/bin/browseros-cli"
    elif [ -f "/usr/local/bin/browseros-cli" ]; then
        export BROWSEROS_CLI="/usr/local/bin/browseros-cli"
    fi
fi
BROWSEROS_CLI="${BROWSEROS_CLI:-browseros-cli}"

# Selectors — overridable via environment
SELECTOR_INPUT="${SELECTOR_INPUT:-div[contenteditable=\"true\"]}"
SELECTOR_IMAGE="${SELECTOR_IMAGE:-img[alt=\"Generated image\"]}"
SELECTOR_DOWNLOAD="${SELECTOR_DOWNLOAD:-[aria-label=\"Download\"]}"
SELECTOR_MAKE_VIDEO="${SELECTOR_MAKE_VIDEO:-[aria-label=\"Make video\"]}"

_bos() {
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

bos_health() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        return 0
    fi
    local output
    output=$(_bos health 2>/dev/null)
    if [ $? -eq 0 ] && echo "$output" | grep -qi "ok"; then
        return 0
    fi
    return 1
}

bos_navigate() {
    local url="$1"
    _bos nav "$url"
}

bos_eval() {
    local js="$1"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] eval: ${js:0:80}..."
        echo '{"result":"https://grok.com/imagine/post/dry-run-test"}'
        return 0
    fi
    local output
    output=$(_bos eval "$js" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log ERROR "bos_eval failed for: $js"
        return 1
    fi
    echo "$output"
}

bos_snap() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo '[9999] button "Download"'
        return 0
    fi
    _bos snap
}

bos_get_snap_ref() {
    local pattern="$1"
    local snapshot_text
    snapshot_text=$(bos_snap)
    if [ $? -ne 0 ]; then
        return 1
    fi
    local ref
    ref=$(echo "$snapshot_text" | grep -i "$pattern" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    return 1
}

bos_find_element_coords() {
    local selector="$1"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] Finding element: $selector"
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
    bos_eval "$js"
}

bos_find_element() {
    local selector="$1"
    local timeout="${2:-30}"
    local interval=2
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local output
        output=$(bos_find_element_coords "$selector")
        if [ $? -eq 0 ]; then
            local found
            found=$(echo "$output" | jq -r '.found // false' 2>/dev/null)
            if [ "$found" = "true" ]; then
                echo "$output"
                return 0
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    log WARN "Element not found: $selector (timeout ${timeout}s)"
    return 1
}

bos_click_at() {
    local x="$1"
    local y="$2"
    _bos click-at "$x" "$y"
}

bos_click() {
    local ref="$1"
    _bos click "$ref"
}

bos_click_by_snap_pattern() {
    local pattern="$1"
    local ref
    ref=$(bos_get_snap_ref "$pattern")
    if [ $? -ne 0 ] || [ -z "$ref" ]; then
        log WARN "Could not find snapshot ref for pattern: $pattern"
        return 1
    fi
    bos_click "$ref"
}

bos_get_first_link_ref() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        return 1
    fi
    local snap_output
    snap_output=$(bos_snap)
    if [ $? -ne 0 ]; then
        return 1
    fi
    local snapshot_text
    snapshot_text=$(echo "$snap_output" | jq -r '.snapshot // empty' 2>/dev/null)
    if [ -z "$snapshot_text" ]; then
        return 1
    fi
    local ref
    ref=$(echo "$snapshot_text" | grep -E '^\[[0-9]+\][[:space:]]+link[[:space:]]+' | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    return 1
}

bos_click_first_link() {
    local ref
    ref=$(bos_get_first_link_ref)
    if [ $? -ne 0 ] || [ -z "$ref" ]; then
        log WARN "Could not find first link element in snapshot"
        return 1
    fi
    log INFO "Clicking first link element [ref: $ref]"
    bos_click "$ref"
}

bos_fill() {
    local ref="$1"
    local text="$2"
    _bos fill "$ref" "$text"
}

bos_key() {
    local key="$1"
    _bos key "$key"
}

bos_type_text() {
    local text="$1"
    local input_info
    local input_ref=""
    local input_x=""
    local input_y=""

    input_info=$(bos_find_element "$SELECTOR_INPUT" 10)
    if [ $? -eq 0 ] && [ -n "$input_info" ]; then
        input_x=$(echo "$input_info" | jq -r '.x // empty' 2>/dev/null)
        input_y=$(echo "$input_info" | jq -r '.y // empty' 2>/dev/null)
    fi

    if [ -n "$input_x" ] && [ -n "$input_y" ]; then
        log DEBUG "Using click-at + eval fallback on coordinates $input_x,$input_y"
        bos_click_at "$input_x" "$input_y"
    else
        log ERROR "Could not find input coordinates"
        return 1
    fi

    # Escape text for JS injection
    local escaped_text
    escaped_text=$(echo "$text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    local js
    js="(function() { var el = document.querySelector('$SELECTOR_INPUT'); if (!el) return JSON.stringify({success: false, error: 'not found'}); el.innerText = \"$escaped_text\"; el.dispatchEvent(new Event('input', {bubbles: true})); return JSON.stringify({success: true}); })()"

    bos_eval "$js"
}

bos_download() {
    local ref="$1"
    local dest_dir="$2"
    _bos download "$ref" "$dest_dir"
}

download_with_curl_fallback() {
    local ref="$1"
    local dest_dir="$2"
    
    # Try browseros-cli download first
    if [ "${DRY_RUN:-0}" != "1" ]; then
        bos_download "$ref" "$dest_dir"
        if [ $? -eq 0 ]; then
            return 0
        fi
        log WARN "browseros-cli download failed, trying curl fallback"
    fi

    # Fallback: extract video URL and curl it
    local video_url
    video_url=$(bos_eval "document.querySelector('video')?.src || ''")
    if [ $? -eq 0 ] && [ -n "$video_url" ] && [ "$video_url" != '""' ]; then
        local url
        url=$(echo "$video_url" | jq -r '.result // empty' 2>/dev/null)
        if [ -n "$url" ]; then
            local filename
            filename=$(basename "$url" | cut -d'?' -f1)
            [ -z "$filename" ] && filename="video.mp4"
            curl -L -o "$dest_dir/$filename" "$url"
            return $?
        fi
    fi
    return 1
}

bos_wait_for() {
    local condition_fn="$1"
    local interval="${2:-5}"
    local timeout="${3:-120}"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] Skipping wait loop"
        return 0
    fi
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if eval "$condition_fn" > /dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    log WARN "Wait condition timed out after ${timeout}s"
    return 1
}

bos_get_page_url() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "https://grok.com/imagine/post/dry-run-test"
        return 0
    fi
    local output
    output=$(bos_eval "window.location.href")
    echo "$output" | jq -r '.result // empty' 2>/dev/null || echo "$output"
}

retry_with_backoff() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    while [ "$attempt" -le "$max_retries" ]; do
        log DEBUG "Retry attempt $attempt/$max_retries: $cmd"
        if eval "$cmd"; then
            return 0
        fi
        log WARN "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    return 1
}

bos_get_active_page() {
    local output
    output=$(_bos active --json 2>/dev/null)
    echo "$output"
}

bos_open() {
    local url="$1"
    _bos open "$url"
}

bos_text() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "Download"
        return 0
    fi
    _bos text
}

bos_wait_for_text() {
    local text="$1"
    local timeout="${2:-30}"
    _bos wait --text "$text" --wait-timeout "$((timeout * 1000))"
}

bos_wait_for_selector() {
    local selector="$1"
    local timeout="${2:-30}"
    _bos wait --selector "$selector" --wait-timeout "$((timeout * 1000))"
}
