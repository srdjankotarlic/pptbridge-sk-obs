# PPTBridge SK for OBS Setup Guide

**Created by Srđan Kotarlić** | Windows v0.5.10 / Apple Silicon v0.5.11

For the fastest install path, start with [QUICKSTART.md](QUICKSTART.md). This guide is the fuller walkthrough for setup, controls, multiple decks, and troubleshooting.

## What This Is

PPTBridge SK for OBS is a native OBS plugin that adds two real source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

Use it when you want:

- a clean PowerPoint slide feed in program
- a separate presenter view with notes on a stage monitor
- slide control from OBS hotkeys, source buttons, Companion, local OSC, or a show-control surface
- OBS to open quietly until you choose to start PowerPoint

Windows 10/11 x64 and Apple Silicon macOS are stable release platforms. Intel
Mac remains available as a separate v0.4.4 beta while real Intel feedback is
collected.

## Requirements

You need:

- Windows 10/11 x64, Apple Silicon macOS 12+, or an Intel Mac for the beta build
- OBS Studio 30 or newer, 64-bit
- at least one `.pptx` or `.pdf` file
- desktop Microsoft PowerPoint for PowerPoint files and live mode; PDF decks do
  not require PowerPoint

Recommended:

- install Microsoft PowerPoint for the preferred true live mode
- download the package that matches your platform from the
  [Download and Install table](README.md#download-and-install)

## Install The Plugin

### Windows 10/11 x64

1. Download and extract the
   [Windows v0.5.10 ZIP](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.10/pptbridge-obs-windows-x64-v0.5.10.zip)
2. Quit OBS if it is open
3. Double-click `INSTALL.cmd` and approve the administrator prompt
4. Open OBS Studio 30 or newer

Full Windows details: [native-plugin/INSTALL-Windows.md](native-plugin/INSTALL-Windows.md)

### macOS

1. Download and unzip the right ZIP for your Mac:
   - [Apple Silicon v0.5.11 stable](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.11/pptbridge-obs-macos-apple-silicon.zip)
   - [Intel v0.4.4 beta](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip)
2. Quit OBS if it is open
3. Open `START-HERE-macOS.txt`
4. Double-click `1-Install-PPTBridge-SK.command`
5. If macOS blocks the command, right-click it and choose `Open`
6. Let the installer copy the plugin and open OBS
7. If OBS asks about Safe Mode, choose normal launch so third-party plugins load

### macOS Manual Fallback

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
5. Point both sources to the same `.pptx` or `.pdf`

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
If you want `PageDown`/`PageUp` only while OBS is focused, add them to
`PPTBridge SK: Next Slide` and `PPTBridge SK: Previous Slide` in
`Settings > Hotkeys`.

For a Logitech Spotlight or another stage clicker that must work while the
operator uses Chrome, OBS, or another app, enable:

`Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`

This captures common presenter remote keys globally, routes them to the
PPTBridge source in the current OBS program scene, and suppresses those captured
keys from the focused app. It works for PPTX live mode and PDF/cached decks. If
macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility`
and `Input Monitoring`, then restart OBS or toggle the feature again.

Out of the box it captures `PageDown` for next and `PageUp` for previous.
You can still bind supported custom PPTBridge hotkeys in OBS Settings if your
clicker sends unusual keys. Plain typing keys, Space, Return, Tab, Delete, and
normal left/right arrows are deliberately excluded from global capture so the
operator can continue typing and navigating while OBS is open.

## PowerPoint Startup And Shutdown

`PPTBridge SK Slide` source properties include the PowerPoint lifecycle controls:

| Control | What it does |
|---|---|
| `Start / Restart PowerPoint Live Mode` | Opens PowerPoint if needed, starts the slideshow only when you click it, and recovers if the slideshow window was closed |
| `Auto Start PowerPoint When OBS Opens` | Starts the slideshow automatically when OBS loads the source |
| `Auto Recover Live PowerPoint Session` | Restarts a slideshow that closes unexpectedly after the live capture was working |
| `Close PowerPoint Slideshow When OBS Closes` | Closes the live slideshow when OBS quits |
| `Stop PowerPoint Live Mode` | Stops the live slideshow without quitting OBS from the highlighted `PowerPoint Live Start / Stop` group |
| `Reattach Live PowerPoint Window` | Recreates the OBS video connection when PowerPoint is still live but the captured window is missing |
| `PowerPoint Resize Behavior` | Keeps OBS locked to its canvas or lets OBS follow the PowerPoint window shape |
| `Lock OBS Size Against PPT Resize` | Keeps the OBS output stable while you shrink the PowerPoint window on your desktop |
| `Follow Current PPT Window Size` | Makes the OBS output intentionally follow the current PowerPoint window shape |

Default behavior is manual. Leave `Auto Start PowerPoint When OBS Opens` off if
you want OBS to open quietly, then click `Start / Restart PowerPoint Live Mode`
only when you are ready.
If the PowerPoint slideshow window was closed but PowerPoint itself is still
open, click the same `Start / Restart PowerPoint Live Mode` button to
reattach/restart the live session.

Default resize behavior is locked. Use `Lock OBS Output Size` for live shows so
the PowerPoint window can be made smaller on the desktop without changing the
program feed in OBS.

## Multiple Decks In Multiple Scenes

Use this setup when one show has several different presentations:

1. Create one OBS scene per presentation.
2. In each scene, add `PPTBridge SK Slide` for the audience/program output.
3. Add `PPTBridge SK Presenter` for the presenter/confidence view if needed.
4. Select the same `.pptx` in that scene's slide and presenter sources.
5. Click `Start / Restart PowerPoint Live Mode` for each deck you want ready.
6. Change OBS scenes during the show.

PPTBridge identifies each live PowerPoint session by the exact selected deck path
(or its fallback copy), not by whichever PowerPoint window is currently active.
This lets several PPTX decks stay open at the same time while the current OBS
program scene controls the right deck.

## Presenter Workflow

Typical live workflow:

1. Scene A sends `PPTBridge SK Slide` to stream / projector / switcher
2. Scene B sends `PPTBridge SK Presenter` to the speaker monitor
3. The speaker changes slides using the clicker
4. OBS hotkeys move the active presentation

For Companion or Stream Deck control, avoid keyboard simulation. Use OBS
WebSocket or PPTBridge's local OSC listener so slide control still works when
another app has keyboard focus.

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
notes. The presenter source also lets you choose a background color, add a
background image or logo, show a compact cue list, and export that cue list as
a `.txt` file from source properties.

PowerPoint builds, animations, and embedded video are shown through
`PPTBridge SK Slide`. `PPTBridge SK Presenter` stays lightweight and static for
notes, next slide, timer, and layout customization. Live-video presenter
preview is postponed until it can be verified without adding crash risk.

## Current Limitations

- true live PowerPoint mode is the preferred path for builds, animations, and embedded media on macOS
- presenter notes appear only when the `.pptx` actually contains notes pages
- PDF decks do not require PowerPoint, but they do not contain live PowerPoint animations or embedded media playback
- for strict OBS control over locally monitored PowerPoint audio, use the pro routing guide in `native-plugin/PRO-AUDIO-MODE.md`

## Troubleshooting

| Problem | What to do |
|---|---|
| Plugin does not appear in OBS | Restart OBS normally, not Safe Mode |
| Slides do not load | Confirm the `.pptx` or `.pdf` exists and try `Reload Presentation` |
| PowerPoint live mode does not start | Confirm Microsoft PowerPoint is installed and allowed to open the deck |
| Clicker does not move slides | Enable `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off` and grant macOS permissions if prompted. For unusual clickers, also bind the clicker's keys in OBS Hotkeys |
| Notes are missing | Check whether presenter notes exist inside the original `.pptx` |

## Public Release Notes

For public sharing, use the native plugin release asset:

- `native-plugin/release/pptbridge-obs-macos-apple-silicon.zip`

The legacy Python script remains in this repo only as historical reference.
