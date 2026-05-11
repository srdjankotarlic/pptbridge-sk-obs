## PPTBridge SK for OBS v0.4.1

Created by **Srdjan Kotarlic**

PPTBridge SK for OBS is a native macOS OBS plugin for live PowerPoint/PDF workflows.

It adds real OBS source types:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

### Download

- Apple Silicon Macs: `pptbridge-obs-macos-apple-silicon.zip`
- Intel Macs: `pptbridge-obs-macos-intel.zip`

### What is new in v0.4.1

- New `Open PowerPoint / Start Live Mode` button in `PPTBridge SK Slide` properties
- PowerPoint no longer has to launch automatically when OBS opens
- `Auto Start PowerPoint When OBS Opens` restores the previous automatic behavior when wanted
- `Close PowerPoint Slideshow When OBS Closes` can clean up the live slideshow on OBS shutdown
- Manual/default mode lets OBS open quietly, then starts PowerPoint only when you click the button
- Keeps v0.4.0 Companion/OSC control, presenter customization, safer OBS-focused hotkeys, and confidence monitor polish

### What it does

- loads a `.pptx` or `.pdf` directly from OBS source properties
- supports true live PowerPoint playback on macOS when Microsoft PowerPoint is installed
- lets users choose manual or automatic PowerPoint slideshow startup
- creates a clean slide source for program output
- creates a presenter source with notes, next slide preview, and timer
- routes slideshow audio into OBS through the slide source, with dedicated app-audio capture in live mode
- supports Companion/OSC control without relying on keyboard focus
- falls back to cached render mode when live mode is unavailable or disabled

### How to use it

1. Download and unzip the ZIP that matches your Mac:
   - Apple Silicon: `pptbridge-obs-macos-apple-silicon.zip`
   - Intel: `pptbridge-obs-macos-intel.zip`
2. Double-click `1-Install-PPTBridge-SK.command`.
3. If OBS is open, let the installer quit it and continue.
4. Let the installer open OBS.
5. Add `PPTBridge SK Slide` to your program scene.
6. Add `PPTBridge SK Presenter` to your confidence or speaker scene.
7. Point both sources to the same `.pptx` or `.pdf`.
8. In `PPTBridge SK Slide` properties, click `Open PowerPoint / Start Live Mode` when you are ready. If PowerPoint is closed, PPTBridge opens it for you.
9. Turn on `Auto Start PowerPoint When OBS Opens` if you prefer the slideshow to launch automatically with OBS.
10. Keep `Close PowerPoint Slideshow When OBS Closes` on if OBS should close the slideshow when quitting.
11. In OBS Hotkeys, use `2` for next slide and `1` for previous slide, or choose your own bindings.

### Companion / OSC quick setup

1. In OBS, open `Tools > PPTBridge SK: Toggle Local OSC Control`.
2. In Bitfocus Companion, add a `Generic OSC` connection:
   - Host: `127.0.0.1`
   - Port: `57130`
   - Protocol: `UDP`
3. Add button actions that send OSC paths such as:
   - `/pptbridge/next`
   - `/pptbridge/previous`
   - `/pptbridge/first`
   - `/pptbridge/last`
   - `/pptbridge/black`
   - `/pptbridge/reload`

### Included assets

- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-intel.zip`
- `.sha256` checksum files for both downloads

Each ZIP includes:

- `START-HERE-macOS.txt`
- `1-Install-PPTBridge-SK.command`
- `pptbridge-obs.plugin`
- `INSTALL-macOS.md`
- `COMPANION-CONTROL.md`
- `send-osc.sh`

### Notes

- Apple Silicon was runtime-tested locally with OBS manual startup, auto-start, close-on-quit, and Companion/OSC control.
- Intel is cross-built against the Intel OBS 32.1.1 app and should be validated on a real Intel Mac.
- The package is currently unsigned and not notarized.
- Presenter notes appear only when the `.pptx` actually contains PPTX notes pages.
- Presenter source is PPTBridge's own presenter layout, not a direct capture of PowerPoint's native presenter window.
- If you need strict OBS control over locally monitored PowerPoint audio, use the `PRO-AUDIO-MODE.md` guide with BlackHole or Loopback.

### Author

Built and published by **Srdjan Kotarlic**
