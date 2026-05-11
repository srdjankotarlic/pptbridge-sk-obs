# OBS Forums Post Draft

## Title

PPTBridge SK for OBS

## Tagline

Native macOS OBS plugin for PowerPoint/PDF slide and presenter sources.

## Description

PPTBridge SK for OBS is a native macOS OBS plugin created by **Srdjan Kotarlic**.

It adds two real source types to OBS:

- `PPTBridge SK Slide` for the clean audience/program feed
- `PPTBridge SK Presenter` for a speaker confidence view with current slide, next slide, timer, and notes

The goal is to support a real event workflow inside OBS:

- clean PowerPoint slides for program or stream output
- separate presenter view with notes for a stage or confidence monitor
- safe slide control through OBS hotkeys, source buttons, Companion, or local OSC

## What it does

- load a `.pptx` or `.pdf` directly from source properties
- support true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- let OBS open quietly, then start PowerPoint only when you click `Open PowerPoint / Start Live Mode`
- optionally auto-start PowerPoint when OBS opens
- optionally close the live slideshow when OBS quits
- create a clean audience slide source
- create a presenter source with notes, next-slide preview, and timer
- support next / previous / first / last / black screen controls
- ignore OBS hotkeys while another app is focused, so typing elsewhere does not move slides
- support Companion/Stream Deck control through OBS WebSocket or local OSC
- route slideshow audio into OBS through the slide source
- fall back to cached render mode when live mode is unavailable or disabled

## Best use cases

- conferences
- church livestreams
- keynote presentations
- webinars
- corporate events
- speaker confidence monitor setups

## Installation

1. Download the ZIP for your Mac from GitHub Releases:
   - Apple Silicon: `pptbridge-obs-macos-apple-silicon.zip`
   - Intel: `pptbridge-obs-macos-intel.zip`
2. Open `START-HERE-macOS.txt`
3. Double-click `1-Install-PPTBridge-SK.command`
4. Add `PPTBridge SK Slide`
5. Add `PPTBridge SK Presenter`
6. Point both sources to the same `.pptx` or `.pdf`
7. For `.pptx` live mode, click `Open PowerPoint / Start Live Mode` in `PPTBridge SK Slide` properties
8. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`, or use Companion/OSC

## Hotkeys and clickers

Search for `PPTBridge SK` in OBS hotkeys and bind:

- next slide
- previous slide
- toggle black screen
- optional first / last slide

The default safe bindings are:

- `2` for next
- `1` for previous

PPTBridge only acts on hotkeys while OBS is the active app, so typing in another
app will not accidentally move the presentation. You can still bind different
keys or clicker buttons in OBS Settings > Hotkeys.

## Companion / OSC

PPTBridge SK can be controlled without keyboard focus:

- OBS WebSocket can press PPTBridge source property buttons by name
- local OSC can be enabled from `Tools > PPTBridge SK: Toggle Local OSC Control`
- local OSC listens on `127.0.0.1:57130`
- useful paths include `/pptbridge/next`, `/pptbridge/previous`, `/pptbridge/first`, `/pptbridge/last`, `/pptbridge/black`, and `/pptbridge/reload`

## Limitations

- current public build is macOS-focused
- installer is currently unsigned / not notarized
- PowerPoint is required for `.pptx` live mode, while PDF decks work without PowerPoint
- presenter notes appear only when the `.pptx` actually contains notes pages
- presenter source is PPTBridge's own presenter layout, not a direct capture of PowerPoint's native Presenter View

## Links

- GitHub repository: `https://github.com/srdjankotarlic/pptbridge-sk-obs`
- Latest release: `https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest`

## Author

Created by **Srdjan Kotarlic**
