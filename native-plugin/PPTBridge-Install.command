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
PLUGIN_EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/pptbridge-obs"
MACHINE_ARCH="$(uname -m)"

echo ""
echo "PPTBridge SK for OBS"
echo "by Srđan Kotarlić"
echo ""

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first, then run this installer again."
  exit 1
fi

PLUGIN_ARCHES="$(lipo -archs "$PLUGIN_EXECUTABLE" 2>/dev/null || true)"
if [ -z "$PLUGIN_ARCHES" ]; then
  echo "Could not detect the plugin architecture."
  echo "Expected plugin executable:"
  echo "$PLUGIN_EXECUTABLE"
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

case " $PLUGIN_ARCHES " in
  *" $MACHINE_ARCH "*) ;;
  *)
    echo "This installer does not match this Mac."
    echo ""
    echo "This Mac: $MACHINE_ARCH"
    echo "This plugin package: $PLUGIN_ARCHES"
    echo ""
    echo "Download the matching PPTBridge SK macOS ZIP from GitHub:"
    echo "- Apple Silicon Macs: pptbridge-obs-macos-apple-silicon.zip"
    echo "- Intel Macs: pptbridge-obs-macos-intel.zip"
    echo ""
    read -r -p "Press Enter to close..."
    exit 1
    ;;
esac

if pgrep -x "OBS" >/dev/null 2>&1; then
  echo "OBS is currently running."
  echo ""
  echo "PPTBridge SK needs OBS closed while the plugin is copied."
  echo "Please quit OBS manually, then run this installer again."
  echo "This avoids OBS/macOS quit crashes while the plugin is being replaced."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

OBS_EXECUTABLE="/Applications/OBS.app/Contents/MacOS/OBS"
if [ ! -d "/Applications/OBS.app" ]; then
  echo "OBS was not found at /Applications/OBS.app."
  echo "The plugin will still be installed, but install OBS Studio before testing it."
  echo ""
elif [ -x "$OBS_EXECUTABLE" ]; then
  OBS_ARCHES="$(lipo -archs "$OBS_EXECUTABLE" 2>/dev/null || true)"
  if [ -n "$OBS_ARCHES" ]; then
    MATCHING_OBS_ARCH=""
    for arch in $PLUGIN_ARCHES; do
      case " $OBS_ARCHES " in
        *" $arch "*) MATCHING_OBS_ARCH="$arch"; break ;;
      esac
    done
    if [ -z "$MATCHING_OBS_ARCH" ]; then
      echo "Installed OBS does not match this plugin package."
      echo ""
      echo "OBS app architecture: $OBS_ARCHES"
      echo "Plugin architecture: $PLUGIN_ARCHES"
      echo ""
      echo "Install the matching OBS Studio build, or download the matching PPTBridge SK package."
      echo ""
      read -r -p "Press Enter to close..."
      exit 1
    fi
  fi
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
echo "   - Next Slide defaults to 2"
echo "   - Previous Slide defaults to 1"
echo "   - Spotlight/Clicker Capture uses PageDown/PageUp; normal arrows stay free"
echo ""
echo "If OBS asks about Safe Mode, choose normal launch so third-party plugins load."
echo ""
read -r -p "Press Enter to close..."
