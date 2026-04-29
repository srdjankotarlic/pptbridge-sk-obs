#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_PATH="$PROJECT_DIR/build/bundle/pptbridge-obs.plugin"
UNSIGNED_PKG_PATH="$PROJECT_DIR/dist/PPTBridge-SK-for-OBS-Installer.pkg"
SIGNED_PKG_PATH="$PROJECT_DIR/dist/PPTBridge-SK-for-OBS-Installer-signed.pkg"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION, for example: Developer ID Application: Your Name (TEAMID)}"
: "${DEVELOPER_ID_INSTALLER:?Set DEVELOPER_ID_INSTALLER, for example: Developer ID Installer: Your Name (TEAMID)}"

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Run ./build.sh first."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null; then
  echo "Developer ID Application certificate was not found in the keychain:"
  echo "$DEVELOPER_ID_APPLICATION"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_INSTALLER" >/dev/null; then
  echo "Developer ID Installer certificate was not found in the keychain:"
  echo "$DEVELOPER_ID_INSTALLER"
  exit 1
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$BUNDLE_PATH"

"$SCRIPT_DIR/make-pkg.sh"

productsign \
  --force \
  --sign "$DEVELOPER_ID_INSTALLER" \
  "$UNSIGNED_PKG_PATH" \
  "$SIGNED_PKG_PATH"

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  xcrun notarytool submit "$SIGNED_PKG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  xcrun notarytool submit "$SIGNED_PKG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  echo "Signed package created:"
  echo "$SIGNED_PKG_PATH"
  echo ""
  echo "Skipping notarization because no notary credentials were provided."
  echo "Set NOTARYTOOL_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD."
  exit 0
fi

xcrun stapler staple "$SIGNED_PKG_PATH"
spctl -a -t install -vv "$SIGNED_PKG_PATH"

echo ""
echo "Signed and notarized package:"
echo "$SIGNED_PKG_PATH"
