# PPTBridge SK for OBS — Setup Guide

**Created by Srđan Kotarlić** | v0.1.1

## What This Is

PPTBridge SK for OBS is a native macOS OBS plugin that adds two real OBS source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

Use it when you want:

- a clean PowerPoint slide feed in program
- a separate presenter view with notes on a stage monitor
- slide control from OBS hotkeys or a Spotlight-style clicker

## Requirements

You need:

- OBS Studio on macOS
- at least one `.pptx` file
- either LibreOffice or Microsoft PowerPoint installed

Recommended:

- install Microsoft PowerPoint for the preferred true live mode
- install LibreOffice as a compatibility fallback

## Install The Plugin

### Option 1. Recommended

1. Open the release folder
2. Run `PPTBridge-SK-for-OBS-Installer.pkg`
3. Finish the macOS installer
4. Restart OBS

### Option 2. Current User Only

1. Run `Install-PPTBridge-SK.command`
2. Let it copy the plugin into your user OBS plugins folder
3. Restart OBS

## Add The Sources In OBS

After restart:

1. Open OBS
2. In `Sources`, click `+`
3. Add `PPTBridge SK Slide`
4. Add `PPTBridge SK Presenter`
5. Point both sources to the same `.pptx`

Recommended setup:

- `PPTBridge SK Slide` in the program scene
- `PPTBridge SK Presenter` in the stage/confidence scene

## Set Up Hotkeys

1. Open `Settings > Hotkeys`
2. Search for `PPTBridge SK`
3. Bind:
   - `PPTBridge SK: Next Slide`
   - `PPTBridge SK: Previous Slide`
   - `PPTBridge SK: Toggle Black Screen`
   - optional `First Slide` and `Last Slide`

Recommended clicker mapping:

- next = `Right Arrow` or `Page Down`
- previous = `Left Arrow` or `Page Up`

## Presenter Workflow

Typical live workflow:

1. Scene A sends `PPTBridge SK Slide` to stream / projector / switcher
2. Scene B sends `PPTBridge SK Presenter` to the speaker monitor
3. The speaker changes slides using the clicker
4. OBS hotkeys move the active presentation

## What The Presenter View Shows

- current slide
- next slide preview
- presenter notes
- running timer
- black screen badge when enabled

## Current Limitations

- true live PowerPoint mode is the preferred path for builds, animations, and embedded media on macOS
- presenter notes appear only when the `.pptx` actually contains notes pages
- for strict OBS control over locally monitored PowerPoint audio, use the pro routing guide in `native-plugin/PRO-AUDIO-MODE.md`

## Troubleshooting

| Problem | What to do |
|---|---|
| Plugin does not appear in OBS | Restart OBS normally, not Safe Mode |
| Slides do not load | Confirm the `.pptx` exists and try `Reload Presentation` |
| Conversion fails | Install LibreOffice and/or Microsoft PowerPoint |
| Clicker does not move slides | Rebind the hotkeys in OBS |
| Notes are missing | Check whether presenter notes exist inside the original `.pptx` |

## Public Release Notes

For public sharing, use the native plugin release assets in:

- `native-plugin/release/PPTBridge-SK-for-OBS-v0.1.1-macOS`

The legacy Python script remains in this repo only as historical reference.
