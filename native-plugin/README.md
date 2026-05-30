# PPTBridge SK for OBS

**Created by Srdjan Kotarlic**

This folder contains the native OBS plugin version of PPTBridge SK.

The main public release path today is the macOS ZIP for the user's Mac:

- [Download stable Apple Silicon build](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip)
- [Download Intel Mac beta build](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip)
- [Open the latest stable macOS release page](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest)

The Windows beta path is source-only for validation:

- [Download Windows beta source pack](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.0-beta.1/PPTBridge-SK-Windows-Beta-v0.5.0-beta.1-source.zip)
- [Open the Windows beta prerelease page](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.0-beta.1)

It is designed to show up inside OBS as real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

## Current Scope

This native version is built around a practical conference workflow:

- choose a `.pptx` file directly in the source properties
- support true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- let users choose manual or automatic PowerPoint slideshow startup
- capture the live slideshow into `PPTBridge SK Slide` as a real OBS source
- route slideshow audio into the OBS mixer through the slide source, with a built-in gain trim and dedicated PowerPoint app-audio capture in live mode
- expose a clean audience source and a presenter source
- render presenter notes, next-slide preview, and timer in a dedicated PPTBridge presenter layout
- customize the presenter layout, presenter split, preview scaling, preview position, notes font size, notes zoom, notes text position, and notes area
- control slide navigation through OBS frontend hotkeys
- fall back to cached render mode with PDF thumbnails and best-effort media handling when live mode is unavailable or disabled

## Platform Status

- macOS Apple Silicon: stable public release path, tested and packaged
- macOS Intel: v0.4.4 beta download, awaiting more real Intel Mac feedback
- Windows: beta source validation pack, not a final installer yet

## Quick Platform Guide

- `v0.5.0-beta.1` = Windows beta source pack for real Windows OBS build/runtime validation
- `v0.4.6` = Apple Silicon stable release with live PowerPoint control stability, timeout-safe process handling, and cleaner release packaging
- `v0.4.5` = previous Apple Silicon stable release with conservative presenter stability, clearer live controls, and updated docs
- `v0.4.4` = previous macOS stable release with clean public ZIP packages and easy install; current Intel beta
- `v0.4.3` = previous macOS stable release with out-of-the-box Spotlight/Clicker Capture keys, multi-deck live routing, locked PowerPoint resize behavior, manual/automatic PowerPoint lifecycle controls, and Companion/OSC control
- `v0.4.2` = previous macOS stable release with Spotlight/Clicker Capture, multi-deck live routing, locked PowerPoint resize behavior, manual/automatic PowerPoint lifecycle controls, and Companion/OSC control
- `v0.4.1` = previous macOS stable release with manual/automatic PowerPoint lifecycle controls and Companion/OSC control
- `v0.4.0` = previous macOS stable release with Companion/OSC control
- `v0.3.0` = previous macOS stable release with presenter customization
- `v0.2.2` = previous macOS stable release
- If someone asks "which one should I install?", the safe answer today is: M-series Mac users install the Apple Silicon ZIP; older Intel Mac users can test the Intel beta ZIP and send feedback.

## What Problem It Solves

PPTBridge SK is meant for productions where the program feed and the speaker view should not be the same thing.

With this plugin you can:

- send only the slide to program
- keep notes and upcoming-slide context on a separate monitor
- let the speaker drive the deck with OBS hotkeys, Companion/OSC, or optional Spotlight/Clicker Capture
- avoid fragile window-capture or full-screen PowerPoint workarounds

## Why This Is Native

This is an actual OBS source plugin project, not an OBS script:

- CMake-based plugin build
- OBS source registration in `obs_module_load`
- source rendering through libobs graphics
- `.plugin` bundle layout for macOS OBS installs
- native C++ / Objective-C++ source layout for macOS OBS

## Build Requirements

For macOS builds you need:

- OBS Studio installed in `/Applications/OBS.app`
- OBS source tree or SDK headers available locally
- CMake
- Xcode Command Line Tools or Xcode

Optional but recommended:

- Microsoft PowerPoint for the preferred true live mode path
- LibreOffice for the fallback cached-render path when PowerPoint is unavailable

Because the release OBS app on macOS includes the libraries but not the development headers, this project expects:

- `OBS_SOURCE_DIR=/path/to/obs-studio`

That source tree is used only for headers during build.

## Configure

```bash
cmake -S . -B build \
  -DOBS_SOURCE_DIR=/path/to/obs-studio \
  -DOBS_APP_DIR=/Applications/OBS.app
```

## Build

```bash
cmake --build build --config RelWithDebInfo
```

## Install For Current User

```bash
cmake --install build --prefix build/install
./scripts/install-local.sh build/bundle/pptbridge-obs.plugin
```

The local install script copies the plugin into:

`~/Library/Application Support/obs-studio/plugins/pptbridge-obs.plugin`

## One-Click Installers

Two installer options are included:

1. `PPTBridge-Install.command`
   - easiest double-click installer for the current macOS user
   - installs into `~/Library/Application Support/obs-studio/plugins`
   - asks you to quit OBS manually before replacing the plugin
   - opens OBS after a successful install
2. `scripts/make-pkg.sh`
   - builds a distributable `.pkg` installer
   - installs into `/Library/Application Support/obs-studio/plugins`
3. `scripts/make-release.sh`
   - builds a shareable release folder and zip for other laptops
   - includes only the user-facing install files: `START-HERE-macOS.txt`, `1-Install-PPTBridge-SK.command`, `README.md`, and the plugin bundle

Build the package:

```bash
./scripts/make-pkg.sh
./scripts/make-release.sh
```

Result:

- `dist/PPTBridge-SK-for-OBS-Installer.pkg`
- `release/pptbridge-obs-macos-apple-silicon.zip`

For public GitHub releases, upload only `release/pptbridge-obs-macos-apple-silicon.zip`
and its `.sha256` checksum. Do not upload a second longer-named ZIP with the
same contents.

## Public Launch Kit

If you want to publish this properly, these files are prepared for you:

- `PUBLISHING.md`
- `PRO-AUDIO-MODE.md`
- `GITHUB-RELEASE.md`
- `WINDOWS-BETA-RELEASE.md`
- `WINDOWS-ALPHA-TESTING.md`
- `WINDOWS-DEVELOPER-HANDOFF.md`
- `COMPANION-CONTROL.md`
- `OBS-FORUM-POST.md`
- `RELEASE-CHECKLIST.md`
- `SIGNING-AND-NOTARIZATION.md`

## OBS Usage Goal

After installation, the source picker should show:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

Recommended workflow:

1. Add `PPTBridge SK Slide` to the program scene
2. Add `PPTBridge SK Presenter` to the stage confidence scene
3. Point both to the same `.pptx` or `.pdf`
4. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `START - Open PowerPoint / Start Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready
5. Open `Settings > Hotkeys`
6. Bind `PPTBridge SK: Next Slide` and `PPTBridge SK: Previous Slide`
7. Let the speaker drive slides with OBS-focused hotkeys, optional Spotlight/Clicker Capture, Companion, local OSC, or source property buttons

That gives you a clean dual-output workflow:

- program output for audience or stream
- presenter output for the stage monitor

## Multiple Decks

For multi-deck shows, put each `.pptx` in its own OBS scene with its own `PPTBridge SK Slide` source and optional matching `PPTBridge SK Presenter` source. Start live mode for each deck you want ready before the show.

Each live PowerPoint session is matched by its exact staged file path, so multiple open PowerPoint slideshow windows can coexist without Deck 2 attaching to Deck 1. Hotkeys and local OSC still route to the PPTBridge source in the current OBS program scene.

## Slide Control

You can change slides in these native ways:

- bind OBS hotkeys such as `2` for next and `1` for previous, or choose your own narrow clicker bindings
- send local OSC commands from Companion or another show-control tool to `127.0.0.1:57130`
- open source `Properties` and use the built-in buttons:
  - `Previous Slide`
  - `Next Slide`
  - `First Slide`
  - `Last Slide`
  - `Toggle Black Screen`
  - `Reload Presentation`

Quick setup for stage control:

1. In OBS, open `Settings > Hotkeys`
2. Search for `PPTBridge SK`
3. On first launch, PPTBridge SK defaults to `2` for next slide and `1` for previous slide if you have not set your own bindings yet
4. If your clicker sends unusual keys, optionally change `PPTBridge SK: Next Slide` to the key it sends for next
5. If your clicker sends unusual keys, optionally change `PPTBridge SK: Previous Slide` to the key it sends for previous
6. Click `Apply`

After that, the speaker can drive the deck from OBS with the clicker and the active PPTBridge source will move forward/back.
PPTBridge ignores hotkey callbacks while OBS is not the active app, so typing in another app will not move the presentation.
For a Logitech Spotlight or other presenter clicker that should work while the operator uses Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`. It captures `PageDown` or `Right` for next and `PageUp` or `Left` for previous by default. It also captures any custom PPTBridge hotkeys, routes them to the PPTBridge source in the current OBS program scene, and suppresses those captured key presses from the focused app. This works for PPTX live mode and PDF/cached decks.
If macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature again. Normal typing keys such as `1` and `2` will be swallowed while Spotlight/Clicker Capture is enabled if you bind them as custom clicker keys.
For Stream Deck or Bitfocus Companion control that must work while another app is focused, use the OBS WebSocket workflow in `COMPANION-CONTROL.md` instead of keyboard hotkeys.
For direct local OSC, enable `Tools > PPTBridge SK: Toggle Local OSC Control` and send OSC messages such as `/pptbridge/next` to `127.0.0.1:57130`.

## PowerPoint Startup Controls

In `PPTBridge SK Slide` properties:

- `START - Open PowerPoint / Start Live Mode` opens PowerPoint if needed and starts the slideshow on demand from the highlighted `PowerPoint Live Start / Stop` group
- `Auto Start PowerPoint When OBS Opens` restores automatic slideshow startup when OBS loads the source
- `Close PowerPoint Slideshow When OBS Closes` cleans up the running slideshow when OBS quits
- `STOP - Stop PowerPoint Live Mode` stops the live slideshow without quitting OBS from the highlighted `PowerPoint Live Start / Stop` group
- `PowerPoint Resize Behavior` controls whether OBS ignores or follows PowerPoint window resizing
- `Lock OBS Size Against PPT Resize` keeps the OBS program output stable while the desktop PowerPoint window is made smaller
- `Follow Current PPT Window Size` intentionally lets the PowerPoint window shape affect OBS

Default behavior is manual startup, so OBS can open quietly before the operator starts PowerPoint.
Default resize behavior is locked to the OBS canvas.

This plugin does not require the old `pptbridge_obs.py` workflow.
The included installers also remove legacy PPTBridge Python script entries from OBS scene collections.

## Notes

This native pass is focused on the installable OBS source workflow and rendering path.
It is designed to run as a real plugin bundle, without requiring the old Python PPTBridge script to stay loaded in OBS.
On macOS with Microsoft PowerPoint installed, `PPTBridge SK Slide` supports true live mode and lets PowerPoint itself handle slideshow builds, animations, and embedded media.
By default, PowerPoint live mode waits for `START - Open PowerPoint / Start Live Mode` in the highlighted source-property control group so OBS can open without immediately launching a slideshow. If PowerPoint is closed, that button opens it and starts the slideshow. Enable `Auto Start PowerPoint When OBS Opens` if you want the older automatic behavior.
Enable `Close PowerPoint Slideshow When OBS Closes` when the live slideshow should be cleaned up as OBS shuts down.
`PPTBridge SK Presenter` is PPTBridge's own presenter layout, synchronized with the deck and fed by PPTX notes pages and slide thumbnails.
The presenter source exposes balanced, large-preview, large-notes, compact, and confidence-monitor layout presets, plus presenter split, preview scale/position, notes zoom, notes text position, and notes sizing controls.
Live builds, animations, and embedded video stay in `PPTBridge SK Slide`. Presenter-side live video preview is postponed until it can be verified without adding crash risk to OBS.
Presenter notes will only appear when the `.pptx` really contains notes pages for those slides.
If live mode is unavailable or disabled, PPTBridge falls back to cached render mode for compatibility.
If you want strict OBS control over local PowerPoint audio during a live show, see `PRO-AUDIO-MODE.md` for the BlackHole and Loopback routing setups.
