# PPTBridge SK for OBS — Setup Guide

**Created by Srđan Kotarlić** | v0.3.0

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

- Apple Silicon or Intel Mac
- OBS Studio on macOS 12 or newer
- at least one `.pptx` file
- Microsoft PowerPoint installed for `.pptx` live mode

Recommended:

- install Microsoft PowerPoint for the preferred true live mode

## Install The Plugin

### Recommended

1. Download and unzip the right ZIP for your Mac:
   - Apple Silicon: `pptbridge-obs-macos-apple-silicon.zip`
   - Intel: `pptbridge-obs-macos-intel.zip`
2. Quit OBS if it is open
3. Open `START-HERE-macOS.txt`
4. Double-click `Install-PPTBridge-SK.command`
5. If macOS blocks the command, right-click it and choose `Open`
6. Let the installer copy the plugin and open OBS

### Manual Fallback

Copy `pptbridge-obs.plugin` into:

```text
~/Library/Application Support/obs-studio/plugins/
```

Then restart OBS.

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

Safe default mapping:

- next = `2`
- previous = `1`

PPTBridge only acts on those hotkeys while OBS is the active app. You can bind
different keys or a clicker in OBS, but typing in another app will not move the
presentation.

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

## Presenter Customization

`PPTBridge SK Presenter` source properties include layout presets for balanced,
large-preview, large-notes, compact, and confidence-monitor views. You can also
adjust the split between the main slide and the right presenter panel, slide
preview fit/fill/crop behavior, preview scale and position, notes font size,
notes zoom, notes text position, and the split between next-slide preview and
notes.

## Current Limitations

- true live PowerPoint mode is the preferred path for builds, animations, and embedded media on macOS
- presenter notes appear only when the `.pptx` actually contains notes pages
- for strict OBS control over locally monitored PowerPoint audio, use the pro routing guide in `native-plugin/PRO-AUDIO-MODE.md`

## Troubleshooting

| Problem | What to do |
|---|---|
| Plugin does not appear in OBS | Restart OBS normally, not Safe Mode |
| Slides do not load | Confirm the `.pptx` exists and try `Reload Presentation` |
| PowerPoint live mode does not start | Confirm Microsoft PowerPoint is installed and allowed to open the deck |
| Clicker does not move slides | Rebind the hotkeys in OBS |
| Notes are missing | Check whether presenter notes exist inside the original `.pptx` |

## Public Release Notes

For public sharing, use the native plugin release assets in:

- `native-plugin/release/PPTBridge-SK-for-OBS-v0.3.0-macOS-Apple-Silicon`
- `native-plugin/release/PPTBridge-SK-for-OBS-v0.3.0-macOS-Intel`

The legacy Python script remains in this repo only as historical reference.
