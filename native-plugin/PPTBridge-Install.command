#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_PATH="$SCRIPT_DIR/pptbridge-obs.plugin"
if [ ! -d "$BUNDLE_PATH" ]; then
  BUNDLE_PATH="$SCRIPT_DIR/build/bundle/pptbridge-obs.plugin"
fi

LEGACY_CLEANUP_SCRIPT=""
if [ -x "$SCRIPT_DIR/cleanup-legacy-python.sh" ]; then
  LEGACY_CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup-legacy-python.sh"
elif [ -x "$SCRIPT_DIR/scripts/cleanup-legacy-python.sh" ]; then
  LEGACY_CLEANUP_SCRIPT="$SCRIPT_DIR/scripts/cleanup-legacy-python.sh"
fi
TARGET_DIR="$HOME/Library/Application Support/obs-studio/plugins"
TARGET_PATH="$TARGET_DIR/pptbridge-obs.plugin"

echo ""
echo "PPTBridge SK for OBS"
echo "by Srđan Kotarlić"
echo ""

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first or ask Claude/Codex to rebuild it."
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_PATH" >/dev/null 2>&1 || true
fi

if [ -n "$LEGACY_CLEANUP_SCRIPT" ]; then
  "$LEGACY_CLEANUP_SCRIPT"
fi

echo "Installed plugin to:"
echo "$TARGET_PATH"
echo ""
echo "Next:"
echo "1. Restart OBS"
echo "2. Bind slide hotkeys in Settings > Hotkeys"
echo "3. Add source:"
echo "   - PPTBridge SK Slide"
echo "   - PPTBridge SK Presenter"
echo ""
read -r -p "Press Enter to close..."
