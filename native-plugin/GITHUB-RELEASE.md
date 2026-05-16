## PPTBridge SK for OBS v0.4.3

Created by **Srdjan Kotarlic**

PPTBridge SK is a native macOS OBS plugin for live PowerPoint and PDF workflows. It adds two OBS sources:

- `PPTBridge SK Slide` - clean audience/program output
- `PPTBridge SK Presenter` - speaker confidence view with current slide, next slide, timer, and notes

### Start Here

- Quick install: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/QUICKSTART.md
- Full setup guide: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SETUP-GUIDE.md
- FAQ: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md
- Support checklist: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SUPPORT.md

### Which Download Should I Use?

| Your Mac | Download |
| --- | --- |
| M1, M2, M3, or M4 Mac | `pptbridge-obs-macos-apple-silicon.zip` |
| Older Intel Mac | `pptbridge-obs-macos-intel.zip` |

Both downloads have the same feature set. Only the CPU build is different.

### What Is New In v0.4.3

- Spotlight/Clicker Capture now works out-of-the-box with common presenter keys: `PageDown`, `Right`, `Space`, or `Enter` for next and `PageUp` or `Left` for previous
- captured clicker keys route to the PPTBridge source in the current OBS program scene and are suppressed from the focused app, so the operator can use Chrome, OBS, or another app during a presentation
- custom PPTBridge hotkeys are still captured if you bind unusual clicker keys in OBS Settings
- locked PowerPoint resize behavior keeps OBS output stable when the desktop PowerPoint window is made smaller
- highlighted `START - Open PowerPoint / Start Live Mode` button in the `PowerPoint Live Start / Stop` group
- OBS can now open quietly without immediately launching the PowerPoint slideshow
- `Auto Start PowerPoint When OBS Opens` is available if you prefer automatic startup
- `Close PowerPoint Slideshow When OBS Closes` can clean up the slideshow when OBS quits
- highlighted `STOP - Stop PowerPoint Live Mode` can stop the slideshow without quitting OBS
- multi-deck live sessions are matched by exact staged PowerPoint file so several PPTX decks can stay open across scenes
- Keeps Companion/OSC control, presenter customization, safer OBS-focused hotkeys, and confidence monitor polish

### Basic Setup

1. Download and unzip the ZIP that matches your Mac.
2. Open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If OBS is open, let the installer quit it and continue.
5. If macOS blocks the command, right-click it and choose `Open`.
6. Let the installer open OBS.
7. Add `PPTBridge SK Slide` to your program/audience scene.
8. Add `PPTBridge SK Presenter` to your confidence/speaker scene.
9. Select the same `.pptx` or `.pdf` in both sources.
10. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `START - Open PowerPoint / Start Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready.

PDF decks do not require PowerPoint. PPTX live mode requires Microsoft PowerPoint for Mac.

### What The Controls Mean

| Control | Meaning |
| --- | --- |
| `START - Open PowerPoint / Start Live Mode` | Starts the PowerPoint slideshow only when you click it from the highlighted `PowerPoint Live Start / Stop` group |
| `Auto Start PowerPoint When OBS Opens` | Starts PowerPoint automatically when OBS loads the source |
| `Close PowerPoint Slideshow When OBS Closes` | Closes the live slideshow when OBS quits |
| `STOP - Stop PowerPoint Live Mode` | Stops the slideshow from the highlighted `PowerPoint Live Start / Stop` group |
| `PowerPoint Resize Behavior` | Locks OBS output size or lets OBS follow the PowerPoint window shape |
| Multi-deck live matching | Keeps each scene attached to its own `.pptx` even when several PowerPoint slideshows are open |

Default behavior is manual startup. Turn on auto-start only if you want the slideshow to appear as soon as OBS opens.
Default resize behavior is `Lock OBS Output Size`, so shrinking the PowerPoint window on the desktop does not make the OBS program source smaller.

### Slide Control

- OBS hotkeys default to `2` for next slide and `1` for previous slide.
- PPTBridge ignores OBS hotkeys while another app has keyboard focus, so typing elsewhere will not move slides.
- For a Logitech Spotlight or another presenter clicker while the operator uses Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`. It captures `PageDown`, `Right`, `Space`, or `Enter` for next and `PageUp` or `Left` for previous by default, routes them to the current OBS program scene, and suppresses the captured keys from the focused app.
- If macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature again.
- Companion and Stream Deck workflows should use OBS WebSocket or PPTBridge's local OSC listener.
- Local OSC can be enabled in OBS from `Tools > PPTBridge SK: Toggle Local OSC Control`.
- Local OSC listens on `127.0.0.1:57130` and supports `/pptbridge/next`, `/pptbridge/previous`, `/pptbridge/first`, `/pptbridge/last`, `/pptbridge/black`, and `/pptbridge/reload`.

### Included Assets

- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-intel.zip`
- `.sha256` checksum files for both downloads

Each ZIP includes:

- `START-HERE-macOS.txt`
- `1-Install-PPTBridge-SK.command`
- `pptbridge-obs.plugin`
- `INSTALL-macOS.md`
- `COMPANION-CONTROL.md`
- `PRO-AUDIO-MODE.md`
- `send-osc.sh`

### Notes

- Apple Silicon was runtime-tested locally with manual startup, auto-start, close-on-quit, OBS-focused hotkeys, Spotlight/Clicker Capture menu presence, and Companion/OSC control.
- Intel is cross-built against the Intel OBS 32.1.1 app with the same feature set and should be validated on a real Intel Mac.
- The package is currently unsigned and not notarized.
- Presenter notes appear only when the `.pptx` actually contains notes pages.
- `PPTBridge SK Presenter` is PPTBridge's own OBS presenter layout, not a direct capture of PowerPoint's native Presenter View.
- If you need strict OBS control over locally monitored PowerPoint audio, use `PRO-AUDIO-MODE.md` with BlackHole or Loopback.

### Author

Built and published by **Srdjan Kotarlic**
