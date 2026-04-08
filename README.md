# PPTBridge SK for OBS

**Created by Srdjan Kotarlic**

PPTBridge SK for OBS is a native macOS OBS plugin for PowerPoint workflows in live production.

It adds two real OBS source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

The goal is simple:

- send a clean PowerPoint slide feed to program
- keep a separate presenter view with notes on a stage or confidence monitor
- let the speaker move slides with a clicker through OBS hotkeys

## What It Does

- loads a `.pptx` directly from OBS source properties
- creates a clean slide source for the audience feed
- creates a presenter source with notes, next slide preview, and timer
- supports OBS hotkeys for next, previous, first, last, and black screen
- works with clickers that send keys like `Page Down`, `Page Up`, and arrow keys
- tries LibreOffice first, then falls back to Microsoft PowerPoint on macOS when needed

## Best Fit

PPTBridge SK is especially useful for:

- conferences
- church livestreams
- corporate presentations
- webinars
- keynote-style event production
- confidence monitor workflows for speakers on stage

## Quick Start

1. Open [native-plugin](native-plugin)
2. Install with the `.pkg` or the current-user `.command` installer
3. Restart OBS
4. Add `PPTBridge SK Slide` to your program scene
5. Add `PPTBridge SK Presenter` to your stage or speaker scene
6. Point both sources to the same `.pptx`
7. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`

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

## Notes

- Current public build is macOS-focused.
- Animation-heavy PowerPoint decks are flattened during conversion.
- The original Python MVP remains in the repo as reference, but the public product direction is the native `PPTBridge SK for OBS` plugin.
