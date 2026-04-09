#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(sed -n 's/^project(.* VERSION \([0-9.][0-9.]*\).*/\1/p' "$PROJECT_DIR/CMakeLists.txt" | head -n 1)"
BRAND_SLUG="PPTBridge-SK-for-OBS"
RELEASE_DIR="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-macOS"
ZIP_PATH="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-macOS.zip"
BUNDLE_PATH="$PROJECT_DIR/build/bundle/pptbridge-obs.plugin"
PKG_PATH="$PROJECT_DIR/dist/PPTBridge-SK-for-OBS-Installer.pkg"
INSTALLER_NAME="Install-PPTBridge-SK.command"
CHECKSUMS_PATH="$RELEASE_DIR/SHA256SUMS.txt"
ZIP_CHECKSUM_PATH="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-macOS.zip.sha256"

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first."
  exit 1
fi

"$SCRIPT_DIR/make-pkg.sh"

mkdir -p "$PROJECT_DIR/release"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cp -R "$BUNDLE_PATH" "$RELEASE_DIR/pptbridge-obs.plugin"
cp "$PROJECT_DIR/PPTBridge-Install.command" "$RELEASE_DIR/$INSTALLER_NAME"
cp "$PROJECT_DIR/scripts/cleanup-legacy-python.sh" "$RELEASE_DIR/cleanup-legacy-python.sh"
cp "$PKG_PATH" "$RELEASE_DIR/"
cp "$PROJECT_DIR/README.md" "$RELEASE_DIR/README.md"
cp "$PROJECT_DIR/PUBLISHING.md" "$RELEASE_DIR/PUBLISHING.md"
cp "$PROJECT_DIR/PRO-AUDIO-MODE.md" "$RELEASE_DIR/PRO-AUDIO-MODE.md"
cp "$PROJECT_DIR/GITHUB-RELEASE.md" "$RELEASE_DIR/GITHUB-RELEASE.md"
cp "$PROJECT_DIR/GITHUB-REPO-METADATA.md" "$RELEASE_DIR/GITHUB-REPO-METADATA.md"
cp "$PROJECT_DIR/LINKEDIN-POST.md" "$RELEASE_DIR/LINKEDIN-POST.md"
cp "$PROJECT_DIR/OBS-FORUM-POST.md" "$RELEASE_DIR/OBS-FORUM-POST.md"
cp "$PROJECT_DIR/RELEASE-CHECKLIST.md" "$RELEASE_DIR/RELEASE-CHECKLIST.md"
cp "$PROJECT_DIR/SCREENSHOT-SHOTLIST.md" "$RELEASE_DIR/SCREENSHOT-SHOTLIST.md"
cp "$PROJECT_DIR/SIGNING-AND-NOTARIZATION.md" "$RELEASE_DIR/SIGNING-AND-NOTARIZATION.md"

chmod +x "$RELEASE_DIR/$INSTALLER_NAME"
chmod +x "$RELEASE_DIR/cleanup-legacy-python.sh"

cat > "$RELEASE_DIR/RELEASE-NOTES.md" <<EOF
# PPTBridge SK for OBS

Version: $VERSION
Author: Srđan Kotarlić

Included:
- PPTBridge-SK-for-OBS-Installer.pkg
- $INSTALLER_NAME
- pptbridge-obs.plugin
- README.md
- PUBLISHING.md
- PRO-AUDIO-MODE.md
- GITHUB-RELEASE.md
- GITHUB-REPO-METADATA.md
- LINKEDIN-POST.md
- OBS-FORUM-POST.md
- RELEASE-CHECKLIST.md
- SCREENSHOT-SHOTLIST.md
- SIGNING-AND-NOTARIZATION.md

What should appear in OBS:
- PPTBridge SK Slide
- PPTBridge SK Presenter

Install:
1. Use the \`.pkg\` for the cleanest install on another Mac.
2. If needed, use \`$INSTALLER_NAME\` for current-user install.
3. Restart OBS and bind hotkeys in \`Settings > Hotkeys\`.

Runtime note:
- If OBS starts in Safe Mode, third-party plugins are disabled.
- True live PowerPoint mode is the preferred path on macOS when Microsoft PowerPoint is installed.
- If live mode is unavailable or disabled, PPTBridge falls back to cached render mode for compatibility.
EOF

(
  cd "$RELEASE_DIR"
  shasum -a 256 \
    "PPTBridge-SK-for-OBS-Installer.pkg" \
    "$INSTALLER_NAME" \
    "README.md" \
    "PUBLISHING.md" \
    "PRO-AUDIO-MODE.md" \
    "GITHUB-RELEASE.md" \
    "GITHUB-REPO-METADATA.md" \
    "LINKEDIN-POST.md" \
    "OBS-FORUM-POST.md" \
    "RELEASE-CHECKLIST.md" \
    "RELEASE-NOTES.md" \
    "SCREENSHOT-SHOTLIST.md" \
    "SIGNING-AND-NOTARIZATION.md" \
    > "$CHECKSUMS_PATH"
)

/usr/bin/xattr -cr "$RELEASE_DIR" || true

(
  cd "$PROJECT_DIR/release"
  rm -f "$ZIP_PATH"
  /usr/bin/zip -qryX "$(basename "$ZIP_PATH")" "$(basename "$RELEASE_DIR")"
)

shasum -a 256 "$ZIP_PATH" > "$ZIP_CHECKSUM_PATH"

echo ""
echo "Created release folder:"
echo "$RELEASE_DIR"
echo ""
echo "Created release zip:"
echo "$ZIP_PATH"
echo ""
