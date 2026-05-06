#!/usr/bin/env bash
# lib/validation.sh — Validation utilities for Grok automation

validate_file() {
    local path="$1"
    local min_size="${2:-1}"
    if [ ! -f "$path" ]; then
        log ERROR "File not found: $path"
        return 1
    fi
    local size
    size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0)
    if [ "$size" -lt "$min_size" ]; then
        log ERROR "File too small ($size bytes < $min_size): $path"
        return 1
    fi
    return 0
}

validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    fi
    log ERROR "Invalid URL: $url"
    return 1
}

validate_project_id() {
    local id="$1"
    if [[ "$id" =~ ^[1-4]$ ]]; then
        return 0
    fi
    log ERROR "Invalid project ID: $id (must be 1-4)"
    return 1
}
