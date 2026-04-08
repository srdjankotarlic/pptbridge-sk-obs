# PPTBridge SK for OBS

**Created by Srđan Kotarlić**

This folder contains the native OBS plugin version of PPTBridge SK.

It is designed to show up inside OBS as real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

## Current Scope

This native version is built around a practical conference workflow:

- choose a `.pptx` file directly in the source properties
- convert the deck to PDF with LibreOffice
- fall back to Microsoft PowerPoint export on macOS when LibreOffice fails
- render slides natively through macOS APIs
- expose a clean audience source and a presenter source
- control slide navigation through OBS frontend hotkeys

## Why This Is Native

This is an actual OBS source plugin project, not an OBS script:

- CMake-based plugin build
- OBS source registration in `obs_module_load`
- source rendering through libobs graphics
- `.plugin` bundle layout for macOS OBS installs

## Build Requirements

You need:

- OBS Studio installed in `/Applications/OBS.app`
- OBS source tree or SDK headers available locally
- CMake
- Xcode Command Line Tools or Xcode
- LibreOffice installed

Optional but recommended:

- Microsoft PowerPoint for the fallback exporter path

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
- `release/PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`

## Public Launch Kit

If you want to publish this properly, these files are prepared for you:

- `PUBLISHING.md`
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
3. Set `PPTBridge SK: Next Slide` to the key your clicker sends for next, usually `Right Arrow` or `Page Down`
4. Set `PPTBridge SK: Previous Slide` to the key your clicker sends for previous, usually `Left Arrow` or `Page Up`
5. Click `Apply`

After that, the speaker can drive the deck from the stage with the clicker and the active PPTBridge source will move forward/back.

This plugin does not require the old `pptbridge_obs.py` workflow.
The included installers also remove legacy PPTBridge Python script entries from OBS scene collections.

## Notes

This native pass is focused on the installable OBS source workflow and rendering path.
It is designed to run as a real plugin bundle, without requiring the old Python PPTBridge script to stay loaded in OBS.
