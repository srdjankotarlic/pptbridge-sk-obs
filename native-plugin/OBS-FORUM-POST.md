# OBS Forums Post Draft

Updated September 12, 2026. This is prepared copy, not a record of a published forum post.

## Title

PPTBridge SK — PDF and PowerPoint presentations directly in OBS

## Tagline

Free Windows and macOS OBS plugin: present PDFs without PowerPoint or a PDF reader, with clean pages and an optional presenter view.

## Description

PPTBridge SK for OBS is a native Windows and macOS plugin I built for live presentations. Open a PDF directly as an OBS source, without PowerPoint, a separate PDF reader, display capture, or manually exporting each page as an image. It also supports a PowerPoint workflow for presentations that need live playback and speaker notes.

Website / downloads: https://srdjankotarlic.github.io/pptbridge-sk-obs/
Source + releases: https://github.com/srdjankotarlic/pptbridge-sk-obs

It adds two real source types to OBS:

- `PPTBridge SK Slide` for the clean audience/program feed
- `PPTBridge SK Presenter` for a speaker confidence view with current page, next page, timer, cue list, and available PowerPoint notes

The goal is to support a real event workflow inside OBS:

- clean PDF pages or PowerPoint slides for program, stream, recording, or OBS projector output
- separate current/next preview, timer, and cue list for a stage or confidence monitor; embedded notes when available in a PowerPoint file
- safe slide control through OBS hotkeys, source buttons, Companion, or local OSC
- optional Spotlight/Clicker Capture for Logitech Spotlight style presenters while the operator uses other apps

## What it does

- render a `.pdf` natively on Windows or macOS without PowerPoint or a PDF reader
- load a `.pptx` from source properties for the PowerPoint workflow
- support live PowerPoint playback when Microsoft PowerPoint is installed
- let OBS open quietly, then start PowerPoint only when you click `START / RESTART - Open PowerPoint Live Mode` in the highlighted `PowerPoint Live Start / Stop` group
- optionally auto-start PowerPoint when OBS opens
- optionally close the live slideshow when OBS quits
- create a clean audience slide source
- create a presenter source with current/next preview, timer, cue list, and available PowerPoint notes
- support next / previous / first / last / black screen controls
- ignore OBS hotkeys while another app is focused, so typing elsewhere does not move slides
- support Companion/Stream Deck control through OBS WebSocket or local OSC
- route live PowerPoint slideshow audio into OBS through the slide source
- fall back to cached render mode when live mode is unavailable or disabled

## Best use cases

- PDF conference slides and training pages
- PDF agendas, diagrams, and static presentation backups

- conferences
- church livestreams
- keynote presentations
- webinars
- corporate events
- speaker confidence monitor setups

## Installation

1. [Download the package for your Windows or Mac](https://srdjankotarlic.github.io/pptbridge-sk-obs/#install).
2. Follow the included platform installation instructions and restart OBS.
3. Add `PPTBridge SK Slide` to the audience scene and select your `.pdf` or `.pptx`.
4. For a PDF, fit the source and check Next / Previous; PowerPoint Live Start is not needed.
5. Optionally add `PPTBridge SK Presenter` in a separate scene, pointing to the same file, for a speaker display.
6. For `.pptx` live mode, use the `PowerPoint Live Start / Stop` group in the Slide source properties.
7. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`, or use Companion/OSC.

Full PDF walkthrough: https://srdjankotarlic.github.io/pptbridge-sk-obs/guides/pdf-slides-presenter-view-obs.html

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

If a stage clicker needs to work while Chrome, OBS, or another app is focused,
enable `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`. It captures
common presenter keys globally, routes them to the PPTBridge source in the
current OBS program scene, and suppresses those captured key presses from the
focused app. This is optional; leave it off for normal OBS-focused hotkeys.

## Companion / OSC

PPTBridge SK can be controlled without keyboard focus:

- OBS WebSocket can press PPTBridge source property buttons by name
- local OSC can be enabled from `Tools > PPTBridge SK: Local OSC Control On/Off`
- local OSC listens on `127.0.0.1:57130`
- useful paths include `/pptbridge/next`, `/pptbridge/previous`, `/pptbridge/first`, `/pptbridge/last`, `/pptbridge/black`, and `/pptbridge/reload`

## Limitations

- stable packages are available for Windows x64 and Apple Silicon; Intel Mac uses the older v0.4.4 beta
- macOS distribution is currently unsigned / not notarized; follow the included installation instructions
- PowerPoint is required for `.pptx` live mode, while PDF decks work without PowerPoint
- PDF pages are static: no PowerPoint animations, click builds, or embedded audio/video playback
- ordinary PDFs do not carry PowerPoint speaker notes in a standard form; notes appear when the PowerPoint file contains them
- Windows PDF rendering requires an unprotected file; rehearse page layout and controls before a show
- presenter source is PPTBridge's own presenter layout, not a direct capture of PowerPoint's native Presenter View

## Links

- GitHub repository: `https://github.com/srdjankotarlic/pptbridge-sk-obs`
- Downloads by platform: https://srdjankotarlic.github.io/pptbridge-sk-obs/#install
- PDF setup guide: https://srdjankotarlic.github.io/pptbridge-sk-obs/guides/pdf-slides-presenter-view-obs.html

## Author

Created by **Srdjan Kotarlic**
