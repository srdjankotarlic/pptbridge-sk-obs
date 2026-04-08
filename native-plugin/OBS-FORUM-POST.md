# OBS Forums Post Draft

## Title

PPTBridge SK for OBS

## Tagline

Native macOS OBS plugin for PowerPoint slide and presenter sources.

## Description

PPTBridge SK for OBS is a native macOS OBS plugin created by **Srdjan Kotarlic**.

It adds two real source types to OBS:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

The goal is to support a real event workflow inside OBS:

- clean PowerPoint slides for program or stream output
- separate presenter view with notes for a stage or confidence monitor
- clicker-friendly slide control through OBS hotkeys

## What it does

- load a `.pptx` directly from source properties
- create a clean audience slide source
- create a presenter source with notes, next-slide preview, and timer
- support next / previous / first / last / black screen controls
- work with common presenter remotes that send keyboard keys
- try LibreOffice first, then fall back to Microsoft PowerPoint on macOS when needed

## Best use cases

- conferences
- church livestreams
- keynote presentations
- webinars
- corporate events
- speaker confidence monitor setups

## Installation

1. Download the `.pkg` or release zip from GitHub Releases
2. Install the plugin
3. Restart OBS
4. Add `PPTBridge SK Slide`
5. Add `PPTBridge SK Presenter`
6. Point both sources to the same `.pptx`
7. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`

## Hotkeys and clickers

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
- installer is currently unsigned / not notarized

## Links

- GitHub repository: `[paste repo link here]`
- Latest release: `[paste release link here]`

## Author

Created by **Srdjan Kotarlic**
