# GitHub Release Body

## PPTBridge SK for OBS v0.2.2

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

### What is better in v0.2.2

- separate Apple Silicon and Intel macOS ZIP downloads
- installer checks that the downloaded package matches the user's Mac architecture
- installer checks that installed OBS matches the plugin architecture before replacing the old plugin
- GitHub README now makes the correct download obvious for M-series and Intel Macs

### What was better in v0.2.1

- easier install on a second Mac through `Install-PPTBridge-SK.command`
- `START-HERE-macOS.txt` added to the release zip
- installer asks the user to quit OBS before replacing the plugin, clears quarantine, validates the executable, and opens OBS after a successful install
- README install steps now match the public ZIP package
- release zip includes a focused macOS install guide

### What was added in v0.2.0

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

1. Download and unzip the ZIP that matches your Mac:
   - Apple Silicon: `pptbridge-obs-macos-apple-silicon.zip`
   - Intel: `pptbridge-obs-macos-intel.zip`
2. Quit OBS
3. Double-click `Install-PPTBridge-SK.command`
4. Let the installer open OBS
5. Add `PPTBridge SK Slide` to your program scene
6. Add `PPTBridge SK Presenter` to your confidence or speaker scene
7. Point both sources to the same `.pptx`
8. In `PPTBridge SK Slide`, keep `Use True Live PowerPoint Mode` enabled

### Best use case

- conferences
- church / live event productions
- keynote-style presentations
- stage confidence monitor workflows

### Included assets

- `PPTBridge-SK-for-OBS-v0.2.2-macOS-Apple-Silicon.zip`
- `PPTBridge-SK-for-OBS-v0.2.2-macOS-Intel.zip`
- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-intel.zip`
- `PPTBridge-SK-for-OBS-Installer.pkg`
- `Install-PPTBridge-SK.command`
- `START-HERE-macOS.txt`
- `INSTALL-macOS.md`

### Install

1. Download the right macOS ZIP for your Mac
2. Unzip it
3. Quit OBS
4. Double-click `Install-PPTBridge-SK.command`
5. Add `PPTBridge SK Slide` and `PPTBridge SK Presenter`

### Notes

- Apple Silicon was runtime-tested locally; Intel was cross-built against the Intel OBS app and needs feedback from real Intel Macs
- package is currently unsigned and not notarized
- presenter notes appear only when the `.pptx` actually contains PPTX notes pages
- presenter source is PPTBridge's own presenter layout, not a direct capture of PowerPoint's native presenter window
- if you need strict OBS control over locally monitored PowerPoint audio, use the `PRO-AUDIO-MODE.md` guide with BlackHole or Loopback

### Author

Built and published by **Srdjan Kotarlic**
