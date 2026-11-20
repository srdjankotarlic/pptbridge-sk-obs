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
PLUGIN_EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/pptbridge-obs"
MACHINE_ARCH="$(uname -m)"

pause_if_interactive() {
  if [ -t 0 ]; then
    read -r -p "Press Enter to close..." || true
  fi
}

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
  pause_if_interactive
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
    pause_if_interactive
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
  pause_if_interactive
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
      pause_if_interactive
      exit 1
    fi
  fi
fi

mkdir -p "$TARGET_DIR"
WORK_DIR="$(mktemp -d "$TARGET_DIR/.pptbridge-install.XXXXXX")"
STAGED_PATH="$WORK_DIR/pptbridge-obs.plugin"
BACKUP_PATH="$WORK_DIR/previous.plugin"

cleanup() {
  if [ -e "$BACKUP_PATH" ] && [ ! -e "$TARGET_PATH" ]; then
    if ! mv "$BACKUP_PATH" "$TARGET_PATH"; then
      echo "Could not restore the previous plugin. It is available at:"
      echo "$BACKUP_PATH"
      return
    fi
    echo "Previous PPTBridge SK plugin was restored."
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if ! /usr/bin/ditto "$BUNDLE_PATH" "$STAGED_PATH" ||
   [ ! -x "$STAGED_PATH/Contents/MacOS/pptbridge-obs" ] ||
   [ ! -s "$STAGED_PATH/Contents/Resources/locale/en-US.ini" ] ||
   [ ! -s "$STAGED_PATH/Contents/Resources/locale/en-GB.ini" ] ||
   ! /usr/bin/plutil -lint "$STAGED_PATH/Contents/Info.plist" >/dev/null; then
  echo "The plugin bundle is incomplete. Extract the whole ZIP and run the installer again."
  pause_if_interactive
  exit 1
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$STAGED_PATH" >/dev/null 2>&1 || true
fi

if ! /usr/bin/codesign --verify --deep --strict "$STAGED_PATH"; then
  echo "The plugin signature check failed. Download a fresh ZIP from the release page."
  pause_if_interactive
  exit 1
fi

# Keep the installed bundle intact until the staged copy can be activated.
if [ -e "$TARGET_PATH" ]; then
  mv "$TARGET_PATH" "$BACKUP_PATH"
fi
if ! mv "$STAGED_PATH" "$TARGET_PATH"; then
  echo "Could not activate the new plugin bundle."
  pause_if_interactive
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
pause_if_interactive
