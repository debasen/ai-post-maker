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

_bos_check_session_error() {
    local output="$1"
    if echo "$output" | grep -q "Session with given id not found"; then
        return 0
    fi
    if echo "$output" | grep -q "CDP error"; then
        return 0
    fi
    return 1
}

# Selectors — overridable via environment
SELECTOR_INPUT="${SELECTOR_INPUT:-div[contenteditable=\"true\"]}"
SELECTOR_IMAGE="${SELECTOR_IMAGE:-img[alt=\"Generated image\"]}"
SELECTOR_DOWNLOAD="${SELECTOR_DOWNLOAD:-[aria-label=\"Download\"]}"
SELECTOR_MAKE_VIDEO="${SELECTOR_MAKE_VIDEO:-[aria-label=\"Make video\"]}"
SELECTOR_SUBMIT="${SELECTOR_SUBMIT:-button[type=\"submit\"][aria-label=\"Submit\"]}"

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
    log DEBUG "bos_navigate: url=$url"
    local output
    output=$(_bos nav "$url")
    local nav_exit=$?
    if [ $nav_exit -ne 0 ]; then
        if _bos_check_session_error "$output"; then
            log ERROR "CDP session lost during navigation"
            return 2
        fi
        return 1
    fi
}

bos_eval() {
    local js="$1"
    log DEBUG "bos_eval: js='${js:0:120}'"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] eval: ${js:0:80}..."
        echo '{"result":"https://grok.com/imagine/post/dry-run-test"}'
        return 0
    fi
    local output
    output=$(_bos eval "$js" 2>/dev/null)
    local eval_exit=$?
    log DEBUG "bos_eval: exit=$eval_exit output='${output:0:120}'"
    if [ $eval_exit -ne 0 ]; then
        if _bos_check_session_error "$output"; then
            log ERROR "CDP session lost during eval"
            return 2
        fi
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
    log DEBUG "bos_snap: taking snapshot"
    local output
    output=$(_bos snap)
    log DEBUG "bos_snap: lines=$(echo "$output" | wc -l | tr -d ' ')"
    echo "$output"
}

bos_get_snap_ref() {
    local pattern="$1"
    log DEBUG "bos_get_snap_ref: searching for pattern='$pattern'"
    local snapshot_text
    snapshot_text=$(bos_snap)
    local snap_exit=$?
    log DEBUG "bos_get_snap_ref: bos_snap exit=$snap_exit, lines=$(echo "$snapshot_text" | wc -l | tr -d ' ')"
    if [ $snap_exit -ne 0 ]; then
        log WARN "bos_get_snap_ref: bos_snap failed (exit $snap_exit)"
        return 1
    fi
    local matches
    matches=$(echo "$snapshot_text" | grep -i "$pattern")
    log DEBUG "bos_get_snap_ref: grep matches for '$pattern': $(echo "$matches" | wc -l | tr -d ' ') lines"
    log DEBUG "bos_get_snap_ref: match lines: $matches"
    local ref
    ref=$(echo "$matches" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    log DEBUG "bos_get_snap_ref: extracted ref='$ref' from pattern='$pattern'"
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    log DEBUG "bos_get_snap_ref: no ref found for pattern='$pattern'"
    return 1
}

bos_find_element_coords() {
    local selector="$1"
    log DEBUG "bos_find_element_coords: selector='$selector'"
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
    local output
    output=$(bos_eval "$js")
    log DEBUG "bos_find_element_coords: output='${output:0:120}'"
    echo "$output"
}

bos_find_element() {
    local selector="$1"
    local timeout="${2:-30}"
    local interval=2
    local elapsed=0
    log DEBUG "bos_find_element: selector='$selector' timeout=${timeout}s"
    while [ "$elapsed" -lt "$timeout" ]; do
        local output
        output=$(bos_find_element_coords "$selector")
        local coords_exit=$?
        log DEBUG "bos_find_element: attempt elapsed=${elapsed}s exit=$coords_exit output='${output:0:120}'"
        if [ "$coords_exit" -eq 2 ]; then
            log ERROR "CDP session lost, aborting element search for '$selector'"
            return 2
        fi
        if [ $coords_exit -eq 0 ]; then
            local found
            found=$(echo "$output" | jq -r '.found // false' 2>/dev/null)
            if [ "$found" = "true" ]; then
                log INFO "Element found: selector='$selector' coords=$(echo "$output" | jq -c '{x,y}')"
                echo "$output"
                return 0
            fi
            log DEBUG "bos_find_element: found=false, retrying..."
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
    log DEBUG "bos_click_at: x=$x y=$y"
    _bos click-at "$x" "$y"
}

bos_click() {
    local ref="$1"
    log DEBUG "bos_click: ref=$ref"
    _bos click "$ref"
}

bos_click_by_snap_pattern() {
    local pattern="$1"
    log DEBUG "bos_click_by_snap_pattern: pattern='$pattern'"
    local ref
    ref=$(bos_get_snap_ref "$pattern")
    local ref_exit=$?
    log DEBUG "bos_click_by_snap_pattern: ref='$ref' exit=$ref_exit"
    if [ $ref_exit -ne 0 ] || [ -z "$ref" ]; then
        log WARN "Could not find snapshot ref for pattern: $pattern"
        return 1
    fi
    bos_click "$ref"
}

bos_get_first_link_ref() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        return 1
    fi
    log DEBUG "bos_get_first_link_ref: taking snapshot..."
    local snapshot_text
    snapshot_text=$(bos_snap)
    local snap_exit=$?
    log DEBUG "bos_get_first_link_ref: snap_exit=$snap_exit"
    if [ $snap_exit -ne 0 ]; then
        log WARN "bos_get_first_link_ref: bos_snap failed"
        return 1
    fi
    log DEBUG "bos_get_first_link_ref: snapshot_text length=${#snapshot_text}"
    if [ -z "$snapshot_text" ]; then
        log WARN "bos_get_first_link_ref: empty snapshot_text"
        return 1
    fi
    local link_lines
    link_lines=$(echo "$snapshot_text" | grep -E '^\[[0-9]+\][[:space:]]+link[[:space:]]+')
    log DEBUG "bos_get_first_link_ref: link count=$(echo "$link_lines" | wc -l | tr -d ' '), first few: $(echo "$link_lines" | head -3)"
    local ref
    ref=$(echo "$link_lines" | head -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
    log DEBUG "bos_get_first_link_ref: extracted ref='$ref'"
    if [ -n "$ref" ]; then
        echo "$ref"
        return 0
    fi
    log WARN "bos_get_first_link_ref: no link ref found"
    return 1
}

bos_click_first_link() {
    log DEBUG "bos_click_first_link: starting"
    local ref
    ref=$(bos_get_first_link_ref)
    local ref_exit=$?
    log DEBUG "bos_click_first_link: ref='$ref' exit=$ref_exit"
    if [ $ref_exit -ne 0 ] || [ -z "$ref" ]; then
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
    log DEBUG "bos_type_text: text length=${#text} selector='$SELECTOR_INPUT'"
    local input_info
    local input_ref=""
    local input_x=""
    local input_y=""

    input_info=$(bos_find_element "$SELECTOR_INPUT" 10)
    local find_exit=$?
    log DEBUG "bos_type_text: find_element exit=$find_exit input_info='${input_info:0:120}'"
    if [ $find_exit -eq 0 ] && [ -n "$input_info" ]; then
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

    local output
    output=$(bos_eval "$js")
    log DEBUG "bos_type_text: eval output='$output'"
}

bos_download() {
    local ref="$1"
    local dest_dir="$2"
    log DEBUG "bos_download: ref=$ref dest_dir=$dest_dir"
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
    log DEBUG "bos_get_page_url: evaluating window.location.href"
    local output
    output=$(bos_eval "window.location.href")
    local url
    url=$(echo "$output" | jq -r '.result // empty' 2>/dev/null || echo "$output")
    log DEBUG "bos_get_page_url: url='$url'"
    echo "$url"
}

retry_with_backoff() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    log DEBUG "retry_with_backoff: cmd='$cmd' max_retries=$max_retries initial_delay=$delay"
    while [ "$attempt" -le "$max_retries" ]; do
        log DEBUG "Retry attempt $attempt/$max_retries: $cmd"
        if eval "$cmd"; then
            log DEBUG "retry_with_backoff: success on attempt $attempt"
            return 0
        fi
        log WARN "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    log WARN "retry_with_backoff: all $max_retries attempts failed"
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
    log DEBUG "bos_text: fetching page text"
    local output
    output=$(_bos text)
    log DEBUG "bos_text: lines=$(echo "$output" | wc -l | tr -d ' ')"
    echo "$output"
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

bos_check_image_preference() {
    if [ "${DRY_RUN:-0}" = "1" ]; then return 1; fi
    log DEBUG "bos_check_image_preference: checking for image preference dialog..."
    local heading_text
    heading_text=$(bos_eval "(function() { var h = document.evaluate(\"//h3[contains(text(), 'Which image do you prefer to keep?')]\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue; return h ? h.innerText.trim() : ''; })()")
    heading_text=$(echo "$heading_text" | jq -r '.result // empty' 2>/dev/null || echo "$heading_text")
    log DEBUG "bos_check_image_preference: heading_text='${heading_text:0:80}'"
    if echo "$heading_text" | grep -q "Which image do you prefer to keep"; then
        log DEBUG "bos_check_image_preference: dialog DETECTED"
        return 0
    fi
    log DEBUG "bos_check_image_preference: dialog NOT detected"
    return 1
}

bos_handle_image_preference() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] Would check for image preference dialog"
        return 2
    fi
    log DEBUG "bos_handle_image_preference: starting"
    if bos_check_image_preference; then
        log INFO "Image preference dialog detected, looking for Skip button..."
        local skip_ref
        skip_ref=$(bos_get_snap_ref 'Skip')
        log DEBUG "bos_handle_image_preference: skip_ref='$skip_ref'"
        if [ -n "$skip_ref" ]; then
            log INFO "Skip button found: ref $skip_ref, clicking..."
            bos_click "$skip_ref"
            sleep 2
            log DEBUG "bos_handle_image_preference: dialog dismissed"
            return 0
        else
            log WARN "Could not find Skip button in preference dialog"
            return 1
        fi
    fi
    log DEBUG "bos_handle_image_preference: no dialog present"
    return 2
}

bos_check_video_preference() {
    if [ "${DRY_RUN:-0}" = "1" ]; then return 1; fi
    log DEBUG "bos_check_video_preference: checking for video preference dialog..."
    local heading_text
    heading_text=$(bos_eval "(function() { var h = document.evaluate(\"//h3[contains(text(), 'Which video do you prefer to keep?')]\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue; return h ? h.innerText.trim() : ''; })()")
    heading_text=$(echo "$heading_text" | jq -r '.result // empty' 2>/dev/null || echo "$heading_text")
    log DEBUG "bos_check_video_preference: heading_text='${heading_text:0:80}'"
    if echo "$heading_text" | grep -q "Which video do you prefer to keep"; then
        log DEBUG "bos_check_video_preference: dialog DETECTED"
        return 0
    fi
    log DEBUG "bos_check_video_preference: dialog NOT detected"
    return 1
}

bos_handle_video_preference() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log INFO "[DRY-RUN] Would check for video preference dialog"
        return 2
    fi
    log DEBUG "bos_handle_video_preference: starting"
    if bos_check_video_preference; then
        log INFO "Video preference dialog detected, looking for Skip button..."
        local skip_ref
        skip_ref=$(bos_get_snap_ref 'Skip')
        log DEBUG "bos_handle_video_preference: skip_ref='$skip_ref'"
        if [ -n "$skip_ref" ]; then
            log INFO "Skip button found: ref $skip_ref, clicking..."
            bos_click "$skip_ref"
            sleep 2
            log DEBUG "bos_handle_video_preference: dialog dismissed"
            return 0
        else
            log WARN "Could not find Skip button in preference dialog"
            return 1
        fi
    fi
    log DEBUG "bos_handle_video_preference: no dialog present"
    return 2
}
