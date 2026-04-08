# OBS Forums Post Draft

## Title

PPTBridge SK for OBS

## Tagline

Native macOS OBS plugin for PowerPoint slide and presenter sources.

## Description

PPTBridge SK for OBS is a native macOS OBS plugin created by **Srđan Kotarlić**.

It adds two real source types to OBS:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

The plugin is built for live presentation workflows where you want:

- a clean slide feed for program or audience output
- a separate presenter view with notes for the speaker monitor
- slide control through OBS hotkeys and common presenter remotes

## Main features

- direct `.pptx` file selection in OBS source properties
- separate slide and presenter source types
- presenter notes support
- next slide preview
- timer in presenter view
- black screen toggle
- clicker-friendly hotkeys
- LibreOffice conversion with Microsoft PowerPoint fallback on macOS

## Recommended use case

- conferences
- keynotes
- church presentations
- corporate events
- stage confidence monitor workflows

## Installation

1. Download the attached `.pkg` or release zip
2. Install the plugin
3. Restart OBS
4. Add `PPTBridge SK Slide` and `PPTBridge SK Presenter`
5. Bind hotkeys in `Settings > Hotkeys`

## Hotkeys

Search for `PPTBridge SK` in OBS hotkeys and bind:

- next slide
- previous slide
- toggle black screen
- optional first / last slide

Most clickers work if they send:

- `Right Arrow` or `Page Down` for next
- `Left Arrow` or `Page Up` for previous

## Limitations

- animation-heavy PowerPoint decks are flattened during conversion
- embedded media is not preserved like full PowerPoint playback
- current public build is macOS-focused

## Author

Created by **Srđan Kotarlić**
