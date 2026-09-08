#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Thumbwheel Remapper"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_BUNDLE"
ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"

echo "Installed $INSTALL_BUNDLE"
echo "Launch it with: open \"$INSTALL_BUNDLE\""
