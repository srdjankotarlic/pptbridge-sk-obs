# PPTBridge SK for OBS

**Created by Srdjan Kotarlic**

This folder contains the native OBS plugin version of PPTBridge SK.

It is designed to show up inside OBS as real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

## Current Scope

This native version is built around a practical conference workflow:

- choose a `.pptx` file directly in the source properties
- default to true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- capture the live slideshow into `PPTBridge SK Slide` as a real OBS source
- route slideshow audio into the OBS mixer through the slide source, with a built-in gain trim and dedicated PowerPoint app-audio capture in live mode
- expose a clean audience source and a presenter source
- render presenter notes, next-slide preview, and timer in a dedicated PPTBridge presenter layout
- control slide navigation through OBS frontend hotkeys
- fall back to cached render mode with PDF thumbnails and best-effort media handling when live mode is unavailable or disabled

## Platform Status

- macOS: public release path, tested and packaged
- Windows: first native backend is now in the source tree, with PowerPoint-driven slide export, embedded media extraction for fallback playback, presenter render, live slideshow control, and OBS-side live capture/audio attachment attempts
- Windows is not published as a stable release yet because it still needs real Windows runtime validation and packaging

## What Problem It Solves

PPTBridge SK is meant for productions where the program feed and the speaker view should not be the same thing.

With this plugin you can:

- send only the slide to program
- keep notes and upcoming-slide context on a separate monitor
- let the speaker drive the deck with a clicker that maps to OBS hotkeys
- avoid fragile window-capture or full-screen PowerPoint workarounds

## Why This Is Native

This is an actual OBS source plugin project, not an OBS script:

- CMake-based plugin build
- OBS source registration in `obs_module_load`
- source rendering through libobs graphics
- `.plugin` bundle layout for macOS OBS installs
- platform split in `CMakeLists.txt` so macOS and Windows use different native backends

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
   - double-click installer for the current macOS user
   - installs into `~/Library/Application Support/obs-studio/plugins`
2. `scripts/make-pkg.sh`
   - builds a distributable `.pkg` installer
   - installs into `/Library/Application Support/obs-studio/plugins`
3. `scripts/make-release.sh`
   - builds a shareable release folder and zip for other laptops
   - includes the `.pkg`, the user installer, the plugin bundle, and publishing docs

Build the package:

```bash
./scripts/make-pkg.sh
./scripts/make-release.sh
```

Result:

- `dist/PPTBridge-SK-for-OBS-Installer.pkg`
- `release/PPTBridge-SK-for-OBS-v0.1.1-macOS.zip`

## Public Launch Kit

If you want to publish this properly, these files are prepared for you:

- `PUBLISHING.md`
- `PRO-AUDIO-MODE.md`
- `GITHUB-RELEASE.md`
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
3. Point both to the same `.pptx`
4. Open `Settings > Hotkeys`
5. Bind `PPTBridge SK: Next Slide` and `PPTBridge SK: Previous Slide`
6. Let the speaker drive slides with a Spotlight-style clicker

That gives you a clean dual-output workflow:

- program output for audience or stream
- presenter output for the stage monitor

## Slide Control

You can change slides in two native ways:

- bind OBS hotkeys such as `Right Arrow` / `Page Down` for next and `Left Arrow` / `Page Up` for previous
- open source `Properties` and use the built-in buttons:
  - `Previous Slide`
  - `Next Slide`
  - `First Slide`
  - `Last Slide`
  - `Toggle Black Screen`
  - `Reload Presentation`

Quick setup for a Spotlight-style clicker:

1. In OBS, open `Settings > Hotkeys`
2. Search for `PPTBridge SK`
3. On first launch, PPTBridge SK now defaults to `2` for next slide and `1` for previous slide if you have not set your own bindings yet
4. Optionally change `PPTBridge SK: Next Slide` to the key your clicker sends for next, usually `Right Arrow` or `Page Down`
5. Optionally change `PPTBridge SK: Previous Slide` to the key your clicker sends for previous, usually `Left Arrow` or `Page Up`
6. Click `Apply`

After that, the speaker can drive the deck from the stage with the clicker and the active PPTBridge source will move forward/back.

This plugin does not require the old `pptbridge_obs.py` workflow.
The included installers also remove legacy PPTBridge Python script entries from OBS scene collections.

## Notes

This native pass is focused on the installable OBS source workflow and rendering path.
It is designed to run as a real plugin bundle, without requiring the old Python PPTBridge script to stay loaded in OBS.
On macOS with Microsoft PowerPoint installed, `PPTBridge SK Slide` defaults to true live mode and lets PowerPoint itself handle slideshow builds, animations, and embedded media.
`PPTBridge SK Presenter` is PPTBridge's own presenter layout, synchronized with the deck and fed by PPTX notes pages and slide thumbnails.
Presenter notes will only appear when the `.pptx` really contains notes pages for those slides.
If live mode is unavailable or disabled, PPTBridge falls back to cached render mode for compatibility.
If you want strict OBS control over local PowerPoint audio during a live show, see `PRO-AUDIO-MODE.md` for the BlackHole and Loopback routing setups.
For the current Windows engineering status and next steps, see `WINDOWS-PORT.md`.
