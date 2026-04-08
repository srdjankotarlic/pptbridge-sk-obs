#!/bin/bash

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/pptbridge-obs.plugin"
  exit 1
fi

PLUGIN_BUNDLE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEGACY_CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup-legacy-python.sh"
PLUGIN_HOME="$HOME/Library/Application Support/obs-studio/plugins"
TARGET="$PLUGIN_HOME/pptbridge-obs.plugin"

mkdir -p "$PLUGIN_HOME"
rm -rf "$TARGET"
cp -R "$PLUGIN_BUNDLE" "$TARGET"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET" >/dev/null 2>&1 || true
fi

if [ -x "$LEGACY_CLEANUP_SCRIPT" ]; then
  "$LEGACY_CLEANUP_SCRIPT"
fi

echo "Installed to:"
echo "$TARGET"
echo ""
echo "Restart OBS and add either:"
echo "  - PPTBridge SK Slide"
echo "  - PPTBridge SK Presenter"
