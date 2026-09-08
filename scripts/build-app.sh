#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="Thumbwheel Remapper"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Thumbwheel Remapper Local Signing}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
    echo "Run ./scripts/setup-local-signing.sh once, then build again." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

swiftc \
    -O \
    -whole-module-optimization \
    "$ROOT_DIR/main.swift" \
    -o "$MACOS_DIR/ThumbwheelRemapper"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp=none \
    "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
