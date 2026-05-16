#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(sed -n 's/^project(.* VERSION \([0-9.][0-9.]*\).*/\1/p' "$PROJECT_DIR/CMakeLists.txt" | head -n 1)"
BRAND_SLUG="PPTBridge-SK-for-OBS"
RELEASE_SUFFIX="${PPTBRIDGE_RELEASE_SUFFIX:-macOS-Apple-Silicon}"
DOWNLOAD_LABEL="${PPTBRIDGE_DOWNLOAD_LABEL:-Apple Silicon}"
RELEASE_DIR="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-$RELEASE_SUFFIX"
ZIP_PATH="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-$RELEASE_SUFFIX.zip"
STABLE_ZIP_NAME="${PPTBRIDGE_ZIP_NAME:-pptbridge-obs-macos-apple-silicon.zip}"
STABLE_ZIP_PATH="$PROJECT_DIR/release/$STABLE_ZIP_NAME"
BUNDLE_PATH="${PPTBRIDGE_BUNDLE_PATH:-$PROJECT_DIR/build/bundle/pptbridge-obs.plugin}"
DIST_DIR="${PPTBRIDGE_DIST_DIR:-$PROJECT_DIR/dist}"
PKG_PATH="$DIST_DIR/PPTBridge-SK-for-OBS-Installer.pkg"
INSTALLER_NAME="1-Install-PPTBridge-SK.command"
CHECKSUMS_PATH="$RELEASE_DIR/SHA256SUMS.txt"
ZIP_CHECKSUM_PATH="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-$RELEASE_SUFFIX.zip.sha256"
STABLE_ZIP_CHECKSUM_PATH="$PROJECT_DIR/release/$STABLE_ZIP_NAME.sha256"

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "Built plugin bundle not found:"
  echo "$BUNDLE_PATH"
  echo ""
  echo "Build the plugin first."
  exit 1
fi

PPTBRIDGE_BUNDLE_PATH="$BUNDLE_PATH" \
PPTBRIDGE_DIST_DIR="$DIST_DIR" \
"$SCRIPT_DIR/make-pkg.sh"

mkdir -p "$PROJECT_DIR/release"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cp -R "$BUNDLE_PATH" "$RELEASE_DIR/pptbridge-obs.plugin"
cp "$PROJECT_DIR/PPTBridge-Install.command" "$RELEASE_DIR/$INSTALLER_NAME"
cp "$PROJECT_DIR/START-HERE-macOS.txt" "$RELEASE_DIR/START-HERE-macOS.txt"
cp "$PROJECT_DIR/scripts/cleanup-legacy-python.sh" "$RELEASE_DIR/cleanup-legacy-python.sh"
cp "$PKG_PATH" "$RELEASE_DIR/"
cp "$PROJECT_DIR/README.md" "$RELEASE_DIR/README.md"
cp "$PROJECT_DIR/INSTALL-macOS.md" "$RELEASE_DIR/INSTALL-macOS.md"
cp "$PROJECT_DIR/PUBLISHING.md" "$RELEASE_DIR/PUBLISHING.md"
cp "$PROJECT_DIR/COMPANION-CONTROL.md" "$RELEASE_DIR/COMPANION-CONTROL.md"
cp "$PROJECT_DIR/PRO-AUDIO-MODE.md" "$RELEASE_DIR/PRO-AUDIO-MODE.md"
cp "$PROJECT_DIR/GITHUB-RELEASE.md" "$RELEASE_DIR/GITHUB-RELEASE.md"
cp "$PROJECT_DIR/GITHUB-REPO-METADATA.md" "$RELEASE_DIR/GITHUB-REPO-METADATA.md"
cp "$PROJECT_DIR/LINKEDIN-POST.md" "$RELEASE_DIR/LINKEDIN-POST.md"
cp "$PROJECT_DIR/OBS-FORUM-POST.md" "$RELEASE_DIR/OBS-FORUM-POST.md"
cp "$PROJECT_DIR/RELEASE-CHECKLIST.md" "$RELEASE_DIR/RELEASE-CHECKLIST.md"
cp "$PROJECT_DIR/SCREENSHOT-SHOTLIST.md" "$RELEASE_DIR/SCREENSHOT-SHOTLIST.md"
cp "$PROJECT_DIR/SIGNING-AND-NOTARIZATION.md" "$RELEASE_DIR/SIGNING-AND-NOTARIZATION.md"
cp "$PROJECT_DIR/scripts/send-osc.sh" "$RELEASE_DIR/send-osc.sh"

chmod +x "$RELEASE_DIR/$INSTALLER_NAME"
chmod +x "$RELEASE_DIR/cleanup-legacy-python.sh"
chmod +x "$RELEASE_DIR/send-osc.sh"

cat > "$RELEASE_DIR/RELEASE-NOTES.md" <<EOF
# PPTBridge SK for OBS

Version: $VERSION
Author: Srđan Kotarlić
macOS package: $DOWNLOAD_LABEL

Included:
- PPTBridge-SK-for-OBS-Installer.pkg
- START-HERE-macOS.txt
- $INSTALLER_NAME
- pptbridge-obs.plugin
- README.md
- INSTALL-macOS.md
- PUBLISHING.md
- COMPANION-CONTROL.md
- PRO-AUDIO-MODE.md
- GITHUB-RELEASE.md
- GITHUB-REPO-METADATA.md
- LINKEDIN-POST.md
- OBS-FORUM-POST.md
- RELEASE-CHECKLIST.md
- SCREENSHOT-SHOTLIST.md
- SIGNING-AND-NOTARIZATION.md
- send-osc.sh

What should appear in OBS:
- PPTBridge SK Slide
- PPTBridge SK Presenter

What the sources do:
- PPTBridge SK Slide is the clean audience/program slide output.
- PPTBridge SK Presenter is the speaker confidence view with current slide, next slide, timer, and notes.

Install:
1. Double-click \`$INSTALLER_NAME\` for the easiest current-user install.
2. If OBS is open, allow the installer to quit it and continue.
3. The installer will copy the plugin and open OBS.
4. Add \`PPTBridge SK Slide\` or \`PPTBridge SK Presenter\`.
5. If macOS blocks the command, right-click it and choose \`Open\`.
6. If the installer says the package does not match this Mac, download the other macOS ZIP.

Basic OBS setup:
1. Add \`PPTBridge SK Slide\` to the program/audience scene.
2. Add \`PPTBridge SK Presenter\` to the speaker/confidence scene.
3. Select the same .pptx or .pdf in both sources.
4. For .pptx live mode, click \`START - Open PowerPoint / Start Live Mode\` in the highlighted \`PowerPoint Live Start / Stop\` group when you are ready.
5. For PDF decks, PowerPoint is not required.

Multiple PPTX decks:
- Create one OBS scene per deck.
- Select that scene's .pptx in its PPTBridge SK Slide and Presenter sources.
- PPTBridge locks each live PowerPoint session to its exact staged deck file, so several slideshow windows can stay open and scene changes control the right deck.

Spotlight / clicker capture:
- Enable Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture when the stage clicker must work while Chrome, OBS, or another app is focused.
- PPTBridge captures PageDown, Right, Space, or Enter for next and PageUp or Left for previous by default.
- Custom PPTBridge hotkeys are also captured if your presenter sends unusual keys.
- If macOS asks, allow OBS in System Settings > Privacy & Security > Accessibility and Input Monitoring, then restart OBS or toggle the feature again.
- Captured clicker hotkeys drive the PPTBridge source in the current OBS Program scene and are suppressed from the focused app.

Runtime note:
- If OBS starts in Safe Mode, third-party plugins are disabled.
- True live PowerPoint mode is the preferred path on macOS when Microsoft PowerPoint is installed.
- Default PowerPoint startup is manual. Turn on \`Auto Start PowerPoint When OBS Opens\` only if you want OBS to launch the slideshow automatically.
- \`Close PowerPoint Slideshow When OBS Closes\` can clean up the slideshow on OBS quit.
- If live mode is unavailable or disabled, PPTBridge falls back to cached render mode for compatibility.
- Companion/OSC control can send /pptbridge/next, /previous, /first, /last, /black, and /reload to 127.0.0.1:57130.
EOF

(
  cd "$RELEASE_DIR"
  shasum -a 256 \
    "PPTBridge-SK-for-OBS-Installer.pkg" \
    "START-HERE-macOS.txt" \
    "$INSTALLER_NAME" \
    "README.md" \
    "INSTALL-macOS.md" \
    "PUBLISHING.md" \
    "COMPANION-CONTROL.md" \
    "PRO-AUDIO-MODE.md" \
    "GITHUB-RELEASE.md" \
    "GITHUB-REPO-METADATA.md" \
    "LINKEDIN-POST.md" \
    "OBS-FORUM-POST.md" \
    "RELEASE-CHECKLIST.md" \
    "RELEASE-NOTES.md" \
    "SCREENSHOT-SHOTLIST.md" \
    "SIGNING-AND-NOTARIZATION.md" \
    "send-osc.sh" \
    > "$CHECKSUMS_PATH"
)

/usr/bin/xattr -cr "$RELEASE_DIR" || true

(
  cd "$PROJECT_DIR/release"
  rm -f "$ZIP_PATH" "$STABLE_ZIP_PATH"
  /usr/bin/zip -qryX "$(basename "$ZIP_PATH")" "$(basename "$RELEASE_DIR")"
)

cp "$ZIP_PATH" "$STABLE_ZIP_PATH"
(
  cd "$PROJECT_DIR/release"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$ZIP_CHECKSUM_PATH"
  shasum -a 256 "$(basename "$STABLE_ZIP_PATH")" > "$STABLE_ZIP_CHECKSUM_PATH"
)

echo ""
echo "Created release folder:"
echo "$RELEASE_DIR"
echo ""
echo "Created release zip:"
echo "$ZIP_PATH"
echo "$STABLE_ZIP_PATH"
echo ""
