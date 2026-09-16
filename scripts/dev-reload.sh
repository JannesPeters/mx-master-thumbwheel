#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DEV_BUILD_DIR="$BUILD_DIR/.dev"
APP_NAME="Thumbwheel Remapper"
APP_EXECUTABLE="ThumbwheelRemapper"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
INSTALL_EXECUTABLE="$INSTALL_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
STAGING_BUNDLE="$DEV_BUILD_DIR/$APP_NAME.app"
ICON_CACHE="$DEV_BUILD_DIR/AppIcon.icns"
ICON_SCRIPT="$ROOT_DIR/scripts/generate-app-icon.swift"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Thumbwheel Remapper Local Signing}"
POLL_INTERVAL="${POLL_INTERVAL:-0.5}"
DEBOUNCE_INTERVAL="${DEBOUNCE_INTERVAL:-0.25}"

usage() {
    cat <<EOF
Usage: $0 [--once]

Build and reload the installed debug app once, or watch Swift package inputs
and reload after every successful change.

Environment:
  INSTALL_DIR          Installation directory (default: \$HOME/Applications)
  POLL_INTERVAL        Watch polling interval in seconds (default: 0.5)
  DEBOUNCE_INTERVAL    Quiet period before rebuilding in seconds (default: 0.25)
  SIGNING_IDENTITY     Local signing identity to use
EOF
}

require_signing_identity() {
    if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
        echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
        echo "Run ./scripts/setup-local-signing.sh once, then run this again." >&2
        return 1
    fi
}

ensure_icon_cache() {
    mkdir -p "$DEV_BUILD_DIR"

    if [[ ! -f "$ICON_CACHE" || "$ICON_SCRIPT" -nt "$ICON_CACHE" ]]; then
        local iconset_dir="$DEV_BUILD_DIR/AppIcon.iconset"

        echo "Generating app icon..."
        rm -rf "$iconset_dir"
        if ! swift "$ICON_SCRIPT" "$iconset_dir"; then
            echo "Could not generate the app icon." >&2
            return 1
        fi
        if ! iconutil --convert icns "$iconset_dir" --output "$ICON_CACHE"; then
            echo "Could not convert the app icon." >&2
            rm -rf "$iconset_dir"
            return 1
        fi
        rm -rf "$iconset_dir"
    fi
}

build_staged_bundle() {
    local bin_dir

    echo "Building debug executable..."
    if ! swift build \
        --configuration debug \
        --product "$APP_EXECUTABLE" \
        --package-path "$ROOT_DIR"; then
        echo "Debug build failed; leaving the running app unchanged." >&2
        return 1
    fi

    if ! bin_dir="$(swift build \
        --configuration debug \
        --product "$APP_EXECUTABLE" \
        --show-bin-path \
        --package-path "$ROOT_DIR")"; then
        echo "Could not locate the debug build output." >&2
        return 1
    fi

    if [[ ! -x "$bin_dir/$APP_EXECUTABLE" ]]; then
        echo "Debug executable not found at $bin_dir/$APP_EXECUTABLE." >&2
        return 1
    fi

    rm -rf "$STAGING_BUNDLE"
    mkdir -p \
        "$STAGING_BUNDLE/Contents/MacOS" \
        "$STAGING_BUNDLE/Contents/Resources"

    if ! cp "$bin_dir/$APP_EXECUTABLE" \
        "$STAGING_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"; then
        echo "Could not stage the debug executable." >&2
        return 1
    fi
    if ! cp "$ROOT_DIR/Resources/Info.plist" \
        "$STAGING_BUNDLE/Contents/Info.plist"; then
        echo "Could not stage Info.plist." >&2
        return 1
    fi

    if ! ensure_icon_cache; then
        return 1
    fi
    if ! cp "$ICON_CACHE" "$STAGING_BUNDLE/Contents/Resources/AppIcon.icns"; then
        echo "Could not stage the app icon." >&2
        return 1
    fi

    if ! plutil -lint "$STAGING_BUNDLE/Contents/Info.plist"; then
        echo "The staged Info.plist is invalid." >&2
        return 1
    fi
    if ! codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --timestamp=none \
        "$STAGING_BUNDLE"; then
        echo "Could not sign the staged debug bundle." >&2
        return 1
    fi
    if ! codesign --verify --deep --strict "$STAGING_BUNDLE"; then
        echo "The staged debug bundle failed code-signature verification." >&2
        return 1
    fi

    echo "Staged signed debug bundle at $STAGING_BUNDLE"
}

running_target_pids() {
    local pid command

    ps -axo pid=,args= | while read -r pid command; do
        if [[ "$command" == "$INSTALL_EXECUTABLE" ]]; then
            printf '%s\n' "$pid"
        fi
    done
}

stop_running_target() {
    local pids pid deadline remaining

    pids="$(running_target_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping PID $pid ($INSTALL_EXECUTABLE)"
            if ! kill "$pid"; then
                echo "Could not stop PID $pid." >&2
                return 1
            fi
        fi
    done

    deadline=$((SECONDS + 8))
    while :; do
        remaining="$(running_target_pids)"
        [[ -z "$remaining" ]] && return 0
        if (( SECONDS >= deadline )); then
            echo "Timed out waiting for the installed app to stop: $remaining" >&2
            return 1
        fi
        sleep 0.1
    done
}

wait_for_target_process() {
    local deadline pids

    deadline=$((SECONDS + 8))
    while :; do
        pids="$(running_target_pids)"
        if [[ -n "$pids" ]]; then
            echo "Running PID $pids from $INSTALL_EXECUTABLE"
            return 0
        fi
        if (( SECONDS >= deadline )); then
            echo "The installed app did not start from $INSTALL_EXECUTABLE." >&2
            return 1
        fi
        sleep 0.1
    done
}

install_and_launch_staged_bundle() {
    local temporary_bundle backup_bundle

    mkdir -p "$INSTALL_DIR"
    temporary_bundle="$INSTALL_DIR/.$APP_NAME.app.dev-$$"
    backup_bundle="$INSTALL_DIR/.$APP_NAME.app.previous-$$"
    rm -rf "$temporary_bundle" "$backup_bundle"

    if ! ditto "$STAGING_BUNDLE" "$temporary_bundle"; then
        echo "Could not prepare the installed bundle; leaving the running app unchanged." >&2
        rm -rf "$temporary_bundle"
        return 1
    fi
    if ! codesign --verify --deep --strict "$temporary_bundle"; then
        echo "The temporary installed bundle failed code-signature verification." >&2
        rm -rf "$temporary_bundle"
        return 1
    fi

    if ! stop_running_target; then
        rm -rf "$temporary_bundle"
        return 1
    fi

    if [[ -e "$INSTALL_BUNDLE" ]]; then
        if ! mv "$INSTALL_BUNDLE" "$backup_bundle"; then
            echo "Could not move the existing installed bundle aside." >&2
            rm -rf "$temporary_bundle"
            return 1
        fi
    fi

    if ! mv "$temporary_bundle" "$INSTALL_BUNDLE"; then
        echo "Could not install the staged debug bundle." >&2
        if [[ -e "$backup_bundle" ]]; then
            mv "$backup_bundle" "$INSTALL_BUNDLE" || true
        fi
        rm -rf "$temporary_bundle"
        return 1
    fi

    if ! plutil -lint "$INSTALL_BUNDLE/Contents/Info.plist" \
        || ! codesign --verify --deep --strict "$INSTALL_BUNDLE"; then
        echo "The installed debug bundle failed post-install verification." >&2
        rm -rf "$INSTALL_BUNDLE"
        if [[ -e "$backup_bundle" ]]; then
            mv "$backup_bundle" "$INSTALL_BUNDLE" || true
        fi
        return 1
    fi

    if ! open "$INSTALL_BUNDLE"; then
        echo "Could not launch $INSTALL_BUNDLE." >&2
        return 1
    fi
    if ! wait_for_target_process; then
        return 1
    fi

    rm -rf "$backup_bundle"
    echo "Reloaded $INSTALL_BUNDLE"
}

reload_app() {
    if ! require_signing_identity; then
        return 1
    fi
    if ! build_staged_bundle; then
        return 1
    fi
    if ! install_and_launch_staged_bundle; then
        return 1
    fi
}

watched_snapshot() {
    {
        printf '%s\n' \
            "$ROOT_DIR/Package.swift" \
            "$ROOT_DIR/Package.resolved" \
            "$ROOT_DIR/.swiftpm/Package.resolved" \
            "$ROOT_DIR/Resources/Info.plist" \
            "$ICON_SCRIPT"
        if [[ -d "$ROOT_DIR/Sources" ]]; then
            find "$ROOT_DIR/Sources" -type f -print
        fi
    } | LC_ALL=C sort -u | while IFS= read -r path; do
        if [[ -e "$path" ]]; then
            printf '%s|' "$path"
            stat -f '%m:%z' "$path"
        else
            printf '%s|missing\n' "$path"
        fi
    done
}

wait_for_stable_snapshot() {
    local candidate next

    candidate="$1"
    while :; do
        sleep "$DEBOUNCE_INTERVAL"
        next="$(watched_snapshot)"
        if [[ "$next" == "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
        candidate="$next"
    done
}

watch_changes() {
    local last_snapshot current_snapshot stable_snapshot

    trap 'printf "\nStopped development watcher; leaving the installed app in place.\n"; exit 0' INT TERM

    echo "Starting development watcher for $INSTALL_BUNDLE"
    last_snapshot="$(watched_snapshot)"
    if ! reload_app; then
        echo "Initial reload failed; waiting for a source change." >&2
    fi

    while :; do
        sleep "$POLL_INTERVAL"
        current_snapshot="$(watched_snapshot)"
        if [[ "$current_snapshot" == "$last_snapshot" ]]; then
            continue
        fi

        stable_snapshot="$(wait_for_stable_snapshot "$current_snapshot")"
        echo "Detected a source change; reloading..."
        if ! reload_app; then
            echo "Reload failed; the last working app remains in place." >&2
        fi
        last_snapshot="$stable_snapshot"
    done
}

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

case "${1:-}" in
    "")
        watch_changes
        ;;
    --once)
        reload_app
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
