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
BACKUP_PATH="$TARGET_DIR/pptbridge-obs.plugin.previous"

echo ""
echo "PPTBridge SK for OBS"
echo "by Srđan Kotarlić"
echo ""

if [ "$(uname -m)" != "arm64" ]; then
  echo "This public macOS build is for Apple Silicon Macs only."
  echo "Intel macOS support is not included in this release yet."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first or ask Claude/Codex to rebuild it."
  exit 1
fi

if pgrep -x "OBS" >/dev/null 2>&1; then
  echo "OBS is currently running."
  echo "Please quit OBS before installing PPTBridge SK, then run this installer again."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

if [ ! -d "/Applications/OBS.app" ]; then
  echo "OBS was not found at /Applications/OBS.app."
  echo "The plugin will still be installed, but install OBS Studio before testing it."
  echo ""
fi

mkdir -p "$TARGET_DIR"
rm -rf "$BACKUP_PATH"
if [ -d "$TARGET_PATH" ]; then
  mv "$TARGET_PATH" "$BACKUP_PATH"
fi

if ! /usr/bin/ditto "$BUNDLE_PATH" "$TARGET_PATH"; then
  echo "Install failed while copying the plugin."
  if [ -d "$BACKUP_PATH" ]; then
    rm -rf "$TARGET_PATH"
    mv "$BACKUP_PATH" "$TARGET_PATH"
    echo "Previous PPTBridge SK plugin was restored."
  fi
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

chmod +x "$TARGET_PATH/Contents/MacOS/pptbridge-obs" 2>/dev/null || true
rm -rf "$BACKUP_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$SCRIPT_DIR" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "$TARGET_PATH" >/dev/null 2>&1 || true
fi

if command -v codesign >/dev/null 2>&1; then
  SIGN_INFO="$(codesign -dv "$TARGET_PATH" 2>&1 || true)"
  if echo "$SIGN_INFO" | grep -q "TeamIdentifier=not set"; then
    codesign --force --deep --sign - "$TARGET_PATH" >/dev/null 2>&1 || true
  fi
fi

if [ ! -x "$TARGET_PATH/Contents/MacOS/pptbridge-obs" ]; then
  echo "Install completed, but the plugin executable was not found where expected:"
  echo "$TARGET_PATH/Contents/MacOS/pptbridge-obs"
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

if [ -n "$LEGACY_CLEANUP_SCRIPT" ]; then
  "$LEGACY_CLEANUP_SCRIPT"
fi

echo "Installed successfully."
echo ""
echo "Installed plugin to:"
echo "$TARGET_PATH"
echo ""
echo "Opening OBS..."
if [ -d "/Applications/OBS.app" ]; then
  open -a OBS >/dev/null 2>&1 || true
fi
echo ""
echo "Next in OBS:"
echo "1. Add source:"
echo "   - PPTBridge SK Slide"
echo "   - PPTBridge SK Presenter"
echo "2. Check Settings > Hotkeys:"
echo "   - Next Slide defaults to 2 / PageDown / Right / Space"
echo "   - Previous Slide defaults to 1 / PageUp / Left"
echo ""
read -r -p "Press Enter to close..."
