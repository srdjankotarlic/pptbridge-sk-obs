# PPTBridge SK for OBS

**Created by Srđan Kotarlić**

PPTBridge SK is a native macOS OBS plugin that lets you load a PowerPoint presentation into OBS as real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

It is built for a practical live-event workflow:

- a clean slide feed for program / audience
- a presenter feed with notes for the confidence monitor
- clicker-friendly hotkeys for stage control
- `.pptx` loading directly from source properties

## Main Features

- Native OBS plugin bundle for macOS
- Presenter notes extracted from `.pptx`
- Dual-source workflow for clean slides and presenter view
- OBS hotkeys for next / previous / first / last / black
- Works with remotes that send keys like `Page Down`, `Page Up`, and arrows
- Tries LibreOffice first, then falls back to Microsoft PowerPoint on macOS when needed

## Quick Start

1. Open [native-plugin](native-plugin)
2. Use the release package generated into `native-plugin/release/`
3. Install with the `.pkg` or the current-user `.command` installer
4. Restart OBS
5. Add `PPTBridge SK Slide` and `PPTBridge SK Presenter`
6. Bind hotkeys in `Settings > Hotkeys`

## Public Release Files

For public sharing and installation:

- `native-plugin/release/PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
- `native-plugin/dist/PPTBridge-SK-for-OBS-Installer.pkg`
- [PUBLISHING.md](native-plugin/PUBLISHING.md)

## Repo Structure

- [native-plugin](native-plugin) — native plugin source, installers, release scripts, and publish docs
- [SETUP-GUIDE.md](SETUP-GUIDE.md) — end-user setup guide
- [install_deps.sh](install_deps.sh) — developer dependency helper
- [pptbridge_obs.py](pptbridge_obs.py) — legacy Python MVP kept as reference

## Legacy Note

The original Python/browser-source MVP is still in this repository as a reference, but the public product direction is now the native `PPTBridge SK for OBS` plugin.
