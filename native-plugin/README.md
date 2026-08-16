# PPTBridge SK for OBS

**Created by Srdjan Kotarlic**

This folder contains the native OBS plugin version of PPTBridge SK.

The main public release paths are the Windows x64 and Apple Silicon ZIPs:

- [Download stable Windows x64 build](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.10/pptbridge-obs-windows-x64-v0.5.10.zip)
- [Download stable Apple Silicon v0.5.8 build](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.8/pptbridge-obs-macos-apple-silicon.zip)
- [Download Intel Mac beta build](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip)
- [Open the Windows v0.5.10 stable release page](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10)

The Windows release is a minimal binary plugin ZIP with a double-click installer:

- [Download Windows plugin ZIP](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.10/pptbridge-obs-windows-x64-v0.5.10.zip)
- [Open the Windows stable release page](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10)

It is designed to show up inside OBS as real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

## Current Scope

This native version is built around a practical conference workflow:

- choose a PowerPoint file directly in the source properties
- support true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- let users choose manual or automatic PowerPoint slideshow startup
- capture the live slideshow into `PPTBridge SK Slide` as a real OBS source
- route verified embedded slideshow audio into the OBS mixer through the slide source, with a built-in gain trim and an optional permission-dependent PowerPoint app-audio path in live mode
- expose a clean audience source and a presenter source
- render presenter notes, next-slide preview, and timer in a dedicated PPTBridge presenter layout
- customize the presenter layout, presenter split, preview scaling, preview position, notes font size, notes zoom, notes text position, and notes area
- control slide navigation through OBS frontend hotkeys
- fall back to cached render mode with PDF thumbnails and best-effort media handling when live mode is unavailable or disabled

## Platform Status

- macOS Apple Silicon: stable public release path, tested and packaged
- macOS Intel: v0.4.4 beta download, awaiting more real Intel Mac feedback
- Windows: stable runtime-tested binary package with `INSTALL.cmd` for OBS 30+ on Windows 10/11 x64

## Quick Platform Guide

- `v0.5.10` = current Windows x64 stable release with hardened live capture, nested Program-scene routing, same-name deck isolation, bounded transactional caches, safer parallel PDF rendering, and a rollback-safe five-file installer
- `v0.5.9` = previous Windows x64 stable release that added native PDF support
- `v0.5.8` = current Apple Silicon stable release and previous Windows stable release
- `v0.5.7` = previous Apple Silicon stable release with more reliable PowerPoint automation and stronger Start Live regression coverage
- `v0.5.6` = previous Apple Silicon stable release with more reliable manual PowerPoint live start, clearer PDF controls, and PowerPoint-readable live staging
- `v0.5.5` = previous Apple Silicon stable release with faster first preview while notes/media finish preparing in the background
- `v0.5.4` = previous Apple Silicon stable release with safer default hotkeys: `2`/`1`, while normal left/right arrows stay free
- `v0.5.3` = previous Apple Silicon stable release with Companion OSC starter template, expanded OSC feedback, and packaging polish
- `v0.5.2` = previous Apple Silicon stable release with Operator Mode controls, interactive cue checks, OSC status feedback, and clearer menu labels
- `v0.5.1` = previous Apple Silicon stable release with live-mode restart recovery, arrow-key defaults, presenter background customization, and cue-list display/export
- `v0.5.0` = previous Apple Silicon stable release with modification-time cache validation and bounded timeouts on PowerPoint helper calls
- `v0.5.8-windows-beta.1` = previous Windows beta plugin ZIP
- `v0.5.0-beta.1` = previous Windows beta plugin ZIP
- `v0.4.7` = Apple Silicon stable release with faster presenter preparation after live start and final-slide live-mode protection
- `v0.4.6` = previous Apple Silicon stable release with live PowerPoint control stability, timeout-safe process handling, and cleaner release packaging
- `v0.4.5` = previous Apple Silicon stable release with conservative presenter stability, clearer live controls, and updated docs
- `v0.4.4` = previous macOS stable release with clean public ZIP packages and easy install; current Intel beta
- `v0.4.3` = previous macOS stable release with out-of-the-box Spotlight/Clicker Capture keys, multi-deck live routing, locked PowerPoint resize behavior, manual/automatic PowerPoint lifecycle controls, and Companion/OSC control
- `v0.4.2` = previous macOS stable release with Spotlight/Clicker Capture, multi-deck live routing, locked PowerPoint resize behavior, manual/automatic PowerPoint lifecycle controls, and Companion/OSC control
- `v0.4.1` = previous macOS stable release with manual/automatic PowerPoint lifecycle controls and Companion/OSC control
- `v0.4.0` = previous macOS stable release with Companion/OSC control
- `v0.3.0` = previous macOS stable release with presenter customization
- `v0.2.2` = previous macOS stable release
- If someone asks "which one should I install?", the answer is: Windows 10/11 x64 users install the Windows v0.5.10 ZIP; M-series Mac users install the Apple Silicon v0.5.8 ZIP; older Intel Mac users can test the Intel beta ZIP.

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

## Installer And Release Packages

Three installer/package options are included:

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
   - includes the install guide, double-click installer, plugin bundle, Companion/OSC guide and starter map, and local OSC tester

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
- `WINDOWS-RELEASE.md`
- `WINDOWS-TESTING.md`
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
4. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `Start / Restart PowerPoint Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready
5. Open `Settings > Hotkeys`
6. Bind `PPTBridge SK: Next Slide` and `PPTBridge SK: Previous Slide`
7. Let the speaker drive slides with OBS-focused hotkeys, optional Spotlight/Clicker Capture, Companion, local OSC, or source property buttons

In PowerPoint live mode, extra next commands on the final slide are ignored so the slideshow remains open in OBS at the end of the deck.

That gives you a clean dual-output workflow:

- program output for audience or stream
- presenter output for the stage monitor

## Multiple Decks

For multi-deck shows, put each `.pptx` in its own OBS scene with its own `PPTBridge SK Slide` source and optional matching `PPTBridge SK Presenter` source. Start live mode for each deck you want ready before the show.

Each live PowerPoint session is matched by the exact selected deck path (or its fallback copy), so multiple open PowerPoint slideshow windows can coexist without Deck 2 attaching to Deck 1. Hotkeys and local OSC still route to the PPTBridge source in the current OBS program scene.

## Slide Control

You can change slides in these native ways:

- use the default OBS hotkeys `2` for next and `1` for previous, or choose your own focused bindings
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
For a Logitech Spotlight or other presenter clicker that should work while the operator uses Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`. It captures `PageDown` for next and `PageUp` for previous by default. It also captures supported custom PPTBridge hotkeys, but plain typing keys and normal left/right arrows are never captured globally. Captured clicker keys route to the PPTBridge source in the current OBS program scene and are suppressed from the focused app. This works for PPTX live mode and PDF/cached decks.
If macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature again.
For Stream Deck or Bitfocus Companion control that must work while another app is focused, use the OBS WebSocket workflow in `COMPANION-CONTROL.md` instead of keyboard hotkeys.
For direct local OSC, enable `Tools > PPTBridge SK: Local OSC Control On/Off` and send OSC messages such as `/pptbridge/next` to `127.0.0.1:57130`.

## Operator Mode

Each PPTBridge source now has a `Show Control (Operator Mode)` group near the top of source properties.
It keeps the show controls in one place: start/stop live mode, previous/next, current/next cue check buttons, clear cue checks, and optional OSC status feedback.
Use `Show Cue List` in the presenter layout controls when the speaker or operator should see the running cue list on the confidence monitor.
For Companion, `companion/PPTBridge-SK-Companion-OSC-Template.json` provides a Generic OSC starter map with common buttons and status feedback addresses.

## PowerPoint Startup Controls

In `PPTBridge SK Slide` properties for `.pptx` decks:

- `Start / Restart PowerPoint Live Mode` opens PowerPoint if needed, starts the slideshow on demand, and recovers if the slideshow window was closed
- `Auto Start PowerPoint When OBS Opens` restores automatic slideshow startup when OBS loads the source
- `Auto Recover Live PowerPoint Session` restarts a slideshow that closes unexpectedly after the live capture was working
- `Close PowerPoint Slideshow When OBS Closes` cleans up the running slideshow when OBS quits
- `Stop PowerPoint Live Mode` stops the live slideshow without quitting OBS from the highlighted `PowerPoint Live Start / Stop` group
- `Reattach Live PowerPoint Window` rebuilds the OBS video connection without restarting OBS or intentionally stopping the show
- `PowerPoint Resize Behavior` controls whether OBS ignores or follows PowerPoint window resizing
- `Lock OBS Size Against PPT Resize` keeps the OBS program output stable while the desktop PowerPoint window is made smaller
- `Follow Current PPT Window Size` intentionally lets the PowerPoint window shape affect OBS

Default behavior is manual startup, so OBS can open quietly before the operator starts PowerPoint.
An intentional `Stop PowerPoint Live Mode` suppresses automatic recovery until live mode is started again.
Default resize behavior is locked to the OBS canvas.
For PDF decks, these PowerPoint-specific controls are hidden because PowerPoint is not used.

This plugin does not require the old `pptbridge_obs.py` workflow.
The included installers also remove legacy PPTBridge Python script entries from OBS scene collections.

## Notes

This native pass is focused on the installable OBS source workflow and rendering path.
It is designed to run as a real plugin bundle, without requiring the old Python PPTBridge script to stay loaded in OBS.
On macOS with Microsoft PowerPoint installed, `PPTBridge SK Slide` supports true live mode and lets PowerPoint itself handle slideshow builds, animations, and embedded media.
By default, PowerPoint live mode waits for `Start / Restart PowerPoint Live Mode` in the highlighted source-property control group so OBS can open without immediately launching a slideshow. If PowerPoint is closed, that button opens it and starts the slideshow. If the slideshow window was closed but PowerPoint itself is still open, the same button recovers the live session. Enable `Auto Start PowerPoint When OBS Opens` if you want the older automatic behavior.
For PDF decks, PPTBridge renders and controls pages directly, so PowerPoint Live Mode is not shown or required.
Enable `Close PowerPoint Slideshow When OBS Closes` when the live slideshow should be cleaned up as OBS shuts down.
`PPTBridge SK Presenter` is PPTBridge's own presenter layout, synchronized with the deck and fed by PPTX notes pages and slide thumbnails.
The presenter source exposes balanced, large-preview, large-notes, compact, and confidence-monitor layout presets, plus presenter split, preview scale/position, notes zoom, notes text position, notes sizing controls, background color/image controls, and optional cue-list display/export with current, next, and checked cue markers.
Live builds, animations, and embedded video stay in `PPTBridge SK Slide`. Presenter-side live video preview is postponed until it can be verified without adding crash risk to OBS.
Presenter notes will only appear when the `.pptx` really contains notes pages for those slides.
If live mode is unavailable or disabled, PPTBridge falls back to cached render mode for compatibility.
If you want strict OBS control over local PowerPoint audio during a live show, see `PRO-AUDIO-MODE.md` for the BlackHole and Loopback routing setups.
