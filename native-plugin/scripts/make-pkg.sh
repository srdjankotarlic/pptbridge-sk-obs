#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_PATH="${PPTBRIDGE_BUNDLE_PATH:-$PROJECT_DIR/build/bundle/pptbridge-obs.plugin}"
DIST_DIR="${PPTBRIDGE_DIST_DIR:-$PROJECT_DIR/dist}"
PKG_NAME="${PPTBRIDGE_PKG_NAME:-PPTBridge-SK-for-OBS-Installer.pkg}"
PKG_PATH="$DIST_DIR/$PKG_NAME"
INSTALL_LOCATION="/Library/Application Support/obs-studio/plugins"
IDENTIFIER="com.srdjankotarlic.pptbridge-obs.installer"
VERSION="$(sed -n 's/^project(.* VERSION \([0-9.][0-9.]*\).*/\1/p' "$PROJECT_DIR/CMakeLists.txt" | head -n 1)"

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first."
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$PKG_PATH"

pkgbuild \
  --component "$BUNDLE_PATH" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --scripts "$SCRIPT_DIR/pkg-scripts" \
  --install-location "$INSTALL_LOCATION" \
  "$PKG_PATH"

echo ""
echo "Created installer package:"
echo "$PKG_PATH"
echo ""
