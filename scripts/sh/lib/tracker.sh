#!/usr/bin/env bash
# lib/tracker.sh — Python tracker/downloader wrappers

__TRACKER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__TRACKER_REPO_ROOT="$(cd "$__TRACKER_SCRIPT_DIR/../../.." && pwd)"

tracker_resolve_script() {
    local project_id="$1"
    if [ "$project_id" = "3" ]; then
        echo "grok_tracker_v3.py"
    else
        echo "grok_tracker.py"
    fi
}

tracker_resolve_downloader() {
    local project_id="$1"
    if [ "$project_id" = "3" ]; then
        echo "grok_video_downloader_v3.py"
    else
        echo "grok_video_downloader.py"
    fi
}

_tracker_cmd() {
    local project_id="$1"
    shift
    local tracker_script
    tracker_script=$(tracker_resolve_script "$project_id")
    python3 "$__TRACKER_REPO_ROOT/scripts/py/$tracker_script" --project "$project_id" "$@"
}

tracker_get_next() {
    local project_id="$1"
    _tracker_cmd "$project_id" get_next
}

tracker_get_config() {
    local project_id="$1"
    _tracker_cmd "$project_id" get_config
}

tracker_complete() {
    local project_id="$1"
    local prompt_id="$2"
    local video_url="$3"
    local post_url="$4"
    _tracker_cmd "$project_id" complete "$prompt_id" "$video_url" "$post_url"
}

tracker_mark_video_warning() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    if [ "$project_id" = "3" ]; then
        log WARN "mark_video_warning not supported for project 3 (v3 tracker)"
        return 1
    fi
    _tracker_cmd "$project_id" mark_video_warning "$prompt_id" "$post_url"
}

tracker_mark_image_warning() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    if [ "$project_id" = "3" ]; then
        log WARN "mark_image_warning not supported for project 3 (v3 tracker)"
        return 1
    fi
    _tracker_cmd "$project_id" mark_image_warning "$prompt_id" "$post_url"
}

tracker_mark_video_failed() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    _tracker_cmd "$project_id" mark_video_failed "$prompt_id" "$post_url"
}

tracker_mark_image_failed() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    if [ "$project_id" = "3" ]; then
        log WARN "mark_image_failed not supported for project 3 (v3 tracker)"
        return 1
    fi
    _tracker_cmd "$project_id" mark_image_failed "$prompt_id" "$post_url"
}

tracker_mark_failed() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    if [ "$project_id" = "3" ]; then
        _tracker_cmd "$project_id" mark_failed "$prompt_id" "$post_url"
    else
        log WARN "mark_failed is v3-specific; using mark_image_failed instead"
        tracker_mark_image_failed "$project_id" "$prompt_id" "$post_url"
    fi
}

tracker_mark_partial() {
    local project_id="$1"
    local prompt_id="$2"
    local video_url="$3"
    local post_url="$4"
    if [ "$project_id" = "3" ]; then
        _tracker_cmd "$project_id" mark_partial "$prompt_id" "$video_url" "$post_url"
    else
        log WARN "mark_partial is v3-specific; using complete instead"
        tracker_complete "$project_id" "$prompt_id" "$video_url" "$post_url"
    fi
}

tracker_mark_extend_failed() {
    local project_id="$1"
    local prompt_id="$2"
    local post_url="$3"
    if [ "$project_id" = "3" ]; then
        _tracker_cmd "$project_id" mark_extend_failed "$prompt_id" "$post_url"
    else
        log WARN "mark_extend_failed is v3-specific; using mark_video_failed instead"
        tracker_mark_video_failed "$project_id" "$prompt_id" "$post_url"
    fi
}

downloader_process() {
    local project_id="$1"
    local download_dir="$2"
    local record_id="$3"
    local downloader_script
    downloader_script=$(tracker_resolve_downloader "$project_id")
    python3 "$__TRACKER_REPO_ROOT/scripts/py/$downloader_script" \
        --project "$project_id" \
        process_download "$download_dir" "$record_id"
}
