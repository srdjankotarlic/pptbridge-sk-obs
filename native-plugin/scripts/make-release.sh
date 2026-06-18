#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(sed -n 's/^project(.* VERSION \([0-9.][0-9.]*\).*/\1/p' "$PROJECT_DIR/CMakeLists.txt" | head -n 1)"
BRAND_SLUG="PPTBridge-SK-for-OBS"
RELEASE_SUFFIX="${PPTBRIDGE_RELEASE_SUFFIX:-macOS-Apple-Silicon}"
DOWNLOAD_LABEL="${PPTBRIDGE_DOWNLOAD_LABEL:-Apple Silicon}"
RELEASE_STATUS="${PPTBRIDGE_RELEASE_STATUS:-Stable}"
RELEASE_DIR="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-$RELEASE_SUFFIX"
STABLE_ZIP_NAME="${PPTBRIDGE_ZIP_NAME:-pptbridge-obs-macos-apple-silicon.zip}"
STABLE_ZIP_PATH="$PROJECT_DIR/release/$STABLE_ZIP_NAME"
LEGACY_ZIP_PATH="$PROJECT_DIR/release/$BRAND_SLUG-v$VERSION-$RELEASE_SUFFIX.zip"
LEGACY_ZIP_CHECKSUM_PATH="$LEGACY_ZIP_PATH.sha256"
BUNDLE_PATH="${PPTBRIDGE_BUNDLE_PATH:-$PROJECT_DIR/build/bundle/pptbridge-obs.plugin}"
INSTALLER_NAME="1-Install-PPTBridge-SK.command"
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

mkdir -p "$PROJECT_DIR/release"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/companion"
mkdir -p "$RELEASE_DIR/scripts"

cp -R "$BUNDLE_PATH" "$RELEASE_DIR/pptbridge-obs.plugin"
cp "$PROJECT_DIR/PPTBridge-Install.command" "$RELEASE_DIR/$INSTALLER_NAME"
cp "$PROJECT_DIR/START-HERE-macOS.txt" "$RELEASE_DIR/START-HERE-macOS.txt"
cp "$PROJECT_DIR/COMPANION-CONTROL.md" "$RELEASE_DIR/COMPANION-CONTROL.md"
cp "$PROJECT_DIR/companion/PPTBridge-SK-Companion-OSC-Template.json" "$RELEASE_DIR/companion/PPTBridge-SK-Companion-OSC-Template.json"
cp "$PROJECT_DIR/scripts/send-osc.sh" "$RELEASE_DIR/scripts/send-osc.sh"
chmod +x "$RELEASE_DIR/$INSTALLER_NAME"
chmod +x "$RELEASE_DIR/scripts/send-osc.sh"

cat > "$RELEASE_DIR/README.md" <<EOF
# PPTBridge SK for OBS - macOS

Created by **Srdjan Kotarlic**

Package: **$DOWNLOAD_LABEL**
Version: **$VERSION**
Status: **$RELEASE_STATUS**

PPTBridge SK is a native OBS plugin that turns PowerPoint and PDF decks into
OBS sources for live events, conference rooms, webinars, church production, and
similar presentation workflows.

## Included Files

- \`$INSTALLER_NAME\` - double-click installer
- \`START-HERE-macOS.txt\` - quick install and usage guide
- \`pptbridge-obs.plugin\` - the OBS plugin bundle
- \`COMPANION-CONTROL.md\` - Companion, WebSocket, and OSC control guide
- \`companion/PPTBridge-SK-Companion-OSC-Template.json\` - Generic OSC starter map
- \`scripts/send-osc.sh\` - local OSC command tester
- \`README.md\` - this file

## Install

1. Quit OBS if it is open.
2. Double-click \`$INSTALLER_NAME\`.
3. If macOS blocks the command, right-click it and choose \`Open\`.
4. Let the installer copy the plugin and open OBS.
5. In OBS, add \`PPTBridge SK Slide\` or \`PPTBridge SK Presenter\`.
6. If OBS asks about Safe Mode, choose normal launch so third-party plugins load.

If the installer says this package does not match your Mac, download the other
macOS ZIP:

- Apple Silicon: \`pptbridge-obs-macos-apple-silicon.zip\`
- Intel Mac: \`pptbridge-obs-macos-intel.zip\`

## What The Sources Do

- \`PPTBridge SK Slide\` is the clean audience/program slide output.
- \`PPTBridge SK Presenter\` is the speaker confidence view with current slide,
  next slide, timer, notes, and layout customization.

## Basic OBS Setup

1. Add \`PPTBridge SK Slide\` to the program/audience scene.
2. Add \`PPTBridge SK Presenter\` to the speaker/confidence scene.
3. Select the same .pptx or .pdf in both sources.
4. For .pptx live mode, click \`Start / Restart PowerPoint Live Mode\` in the highlighted \`PowerPoint Live Start / Stop\` group when you are ready.
5. Use \`PPTBridge SK Presenter\` for notes, next slide, timer, and confidence-monitor layouts. Live animations and video stay in \`PPTBridge SK Slide\`.
6. For PDF decks, PowerPoint is not required.

In PowerPoint live mode, extra next commands on the final slide are ignored so
the slideshow stays open in OBS at the end of the deck. Presenter notes and
thumbnails are prepared in the background after live mode starts, so the slide
source can appear first while the confidence view catches up.

## Slide Control

- OBS hotkeys default to \`2\` for next slide and \`1\` for previous slide. Normal left/right arrows stay free.
- For a Logitech Spotlight or similar presenter clicker, enable
  \`Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off\`.
- Clicker capture supports PageDown for next and PageUp for previous by default.
- If macOS asks, allow OBS in \`System Settings > Privacy & Security > Accessibility\`
  and \`Input Monitoring\`, then restart OBS.

## Multiple PPTX Decks

- Create one OBS scene per deck.
- Select that scene's .pptx in its PPTBridge SK Slide and Presenter sources.
- PPTBridge locks each live PowerPoint session to its exact staged deck file, so several slideshow windows can stay open and scene changes control the right deck.

## Companion / OSC

Enable \`Tools > PPTBridge SK: Local OSC Control On/Off\` in OBS, then send
Generic OSC messages to \`127.0.0.1:57130\`.

Common control paths are \`/pptbridge/next\`, \`/pptbridge/previous\`,
\`/pptbridge/first\`, \`/pptbridge/last\`, \`/pptbridge/black\`, and
\`/pptbridge/reload\`.

Use \`COMPANION-CONTROL.md\` and
\`companion/PPTBridge-SK-Companion-OSC-Template.json\` as the Companion setup
map. Optional status feedback can send slide number, deck/source name,
loading/error state, timer, live state, and cue checked state to
\`127.0.0.1:57131\`.

## Requirements

- macOS 12 or newer
- OBS Studio 30 or newer
- Microsoft PowerPoint for live .pptx mode

PDF decks work without PowerPoint.

## Support

Project page and latest downloads:

https://github.com/srdjankotarlic/pptbridge-sk-obs

Report issues here:

https://github.com/srdjankotarlic/pptbridge-sk-obs/issues
EOF

/usr/bin/xattr -cr "$RELEASE_DIR" || true
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$RELEASE_DIR/pptbridge-obs.plugin"
fi

(
  cd "$PROJECT_DIR/release"
  rm -f "$STABLE_ZIP_PATH" "$LEGACY_ZIP_PATH" "$LEGACY_ZIP_CHECKSUM_PATH"
  /usr/bin/zip -qryX "$(basename "$STABLE_ZIP_PATH")" "$(basename "$RELEASE_DIR")"
  shasum -a 256 "$(basename "$STABLE_ZIP_PATH")" > "$STABLE_ZIP_CHECKSUM_PATH"
)

echo ""
echo "Created release folder:"
echo "$RELEASE_DIR"
echo ""
echo "Created release zip:"
echo "$STABLE_ZIP_PATH"
echo ""
