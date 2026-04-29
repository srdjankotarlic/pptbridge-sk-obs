# GitHub Release Body

## PPTBridge SK for OBS v0.2.0

Created by **Srdjan Kotarlic**

PPTBridge SK for OBS is a native macOS OBS plugin that adds real PowerPoint source types to OBS:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

### What it does

- loads a `.pptx` directly from OBS source properties
- defaults to true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- creates a clean slide source for program output
- creates a presenter source with notes, next slide preview, and timer
- supports clicker-friendly OBS hotkeys
- routes slideshow audio into OBS through the slide source, with dedicated app-audio capture in live mode
- falls back to cached render mode when live mode is unavailable or disabled

### What is better in v0.2.0

- multi-deck scene routing for shows with different decks per scene
- native multi-page PDF support on macOS
- Logitech Spotlight-friendly background hotkey defaults
- windowed PowerPoint slideshow mode with automatic title-bar crop
- deck cache moved into `~/Library/Application Support/PPTBridge SK/cache` for macOS 26 compatibility
- faster live-session attach when PowerPoint is already running the deck
- dedicated app-audio capture path in live mode

### How it works now

- `PPTBridge SK Slide` is the main live show source
- in true live mode, Microsoft PowerPoint runs the slideshow and PPTBridge captures it into OBS
- `PPTBridge SK Presenter` shows PPTBridge's own presenter layout with notes, next slide preview, and timer
- OBS hotkeys move the active presentation

### How to use it

1. Add `PPTBridge SK Slide` to your program scene
2. Add `PPTBridge SK Presenter` to your confidence or speaker scene
3. Point both sources to the same `.pptx`
4. In `PPTBridge SK Slide`, keep `Use True Live PowerPoint Mode` enabled
5. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`
6. For the cleanest live workflow, reuse one existing slide source across scenes with `Add Existing`

### Best use case

- conferences
- church / live event productions
- keynote-style presentations
- stage confidence monitor workflows

### Included assets

- `PPTBridge-SK-for-OBS-v0.2.0-macOS.zip`
- `pptbridge-obs-macos-arm64.zip`
- `PPTBridge-SK-for-OBS-Installer.pkg`

### Install

1. Download the `.pkg` or the release zip
2. Install the plugin
3. Restart OBS
4. Add `PPTBridge SK Slide` and `PPTBridge SK Presenter`
5. Bind `PPTBridge SK` hotkeys in `Settings > Hotkeys`

### Notes

- current public build is macOS-focused
- package is currently unsigned and not notarized
- presenter notes appear only when the `.pptx` actually contains PPTX notes pages
- presenter source is PPTBridge's own presenter layout, not a direct capture of PowerPoint's native presenter window
- if you need strict OBS control over locally monitored PowerPoint audio, use the `PRO-AUDIO-MODE.md` guide with BlackHole or Loopback

### Author

Built and published by **Srdjan Kotarlic**
