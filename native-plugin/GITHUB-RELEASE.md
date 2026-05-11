## PPTBridge SK for OBS v0.4.1

Created by **Srdjan Kotarlic**

PPTBridge SK is a native macOS OBS plugin for live PowerPoint and PDF workflows. It adds two OBS sources:

- `PPTBridge SK Slide` - clean audience/program output
- `PPTBridge SK Presenter` - speaker confidence view with current slide, next slide, timer, and notes

### Which Download Should I Use?

| Your Mac | Download |
| --- | --- |
| M1, M2, M3, or M4 Mac | `pptbridge-obs-macos-apple-silicon.zip` |
| Older Intel Mac | `pptbridge-obs-macos-intel.zip` |

Both downloads have the same feature set. Only the CPU build is different.

### What Is New In v0.4.1

- `Open PowerPoint / Start Live Mode` button in `PPTBridge SK Slide` properties
- OBS can now open quietly without immediately launching the PowerPoint slideshow
- `Auto Start PowerPoint When OBS Opens` is available if you prefer automatic startup
- `Close PowerPoint Slideshow When OBS Closes` can clean up the slideshow when OBS quits
- `Stop PowerPoint Live Mode` can stop the slideshow without quitting OBS
- Keeps v0.4.0 Companion/OSC control, presenter customization, safer OBS-focused hotkeys, and confidence monitor polish

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
10. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `Open PowerPoint / Start Live Mode` when you are ready.

PDF decks do not require PowerPoint. PPTX live mode requires Microsoft PowerPoint for Mac.

### What The Controls Mean

| Control | Meaning |
| --- | --- |
| `Open PowerPoint / Start Live Mode` | Starts the PowerPoint slideshow only when you click it |
| `Auto Start PowerPoint When OBS Opens` | Starts PowerPoint automatically when OBS loads the source |
| `Close PowerPoint Slideshow When OBS Closes` | Closes the live slideshow when OBS quits |
| `Stop PowerPoint Live Mode` | Stops the slideshow from source properties |

Default behavior is manual startup. Turn on auto-start only if you want the slideshow to appear as soon as OBS opens.

### Slide Control

- OBS hotkeys default to `2` for next slide and `1` for previous slide.
- PPTBridge ignores OBS hotkeys while another app has keyboard focus, so typing elsewhere will not move slides.
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

- Apple Silicon was runtime-tested locally with manual startup, auto-start, close-on-quit, OBS-focused hotkeys, and Companion/OSC control.
- Intel is cross-built against the Intel OBS 32.1.1 app with the same feature set and should be validated on a real Intel Mac.
- The package is currently unsigned and not notarized.
- Presenter notes appear only when the `.pptx` actually contains notes pages.
- `PPTBridge SK Presenter` is PPTBridge's own OBS presenter layout, not a direct capture of PowerPoint's native Presenter View.
- If you need strict OBS control over locally monitored PowerPoint audio, use `PRO-AUDIO-MODE.md` with BlackHole or Loopback.

### Author

Built and published by **Srdjan Kotarlic**
