## PPTBridge SK for OBS v0.5.0

Created by **Srdjan Kotarlic**

PPTBridge SK is a native macOS OBS plugin for live PowerPoint and PDF workflows. This release is the **Apple Silicon stable** package. It adds two OBS sources:

- `PPTBridge SK Slide` - clean audience/program output
- `PPTBridge SK Presenter` - speaker confidence view with current slide, next slide, timer, and notes

### Demo Video

Watch a short silent demo of PPTBridge SK running inside OBS:

https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov

### Start Here

- Quick install: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/QUICKSTART.md
- Full setup guide: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SETUP-GUIDE.md
- FAQ: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md
- Support checklist: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SUPPORT.md

### Which Download Should I Use?

| Your Mac | Download | Status |
| --- | --- | --- |
| M1, M2, M3, or M4 Mac | `pptbridge-obs-macos-apple-silicon.zip` | Stable |
| Older Intel Mac | Use v0.4.4 `pptbridge-obs-macos-intel.zip` | Beta |

Apple Silicon is the main stable build. Intel Mac and Windows remain separate beta paths while real-hardware feedback is collected.

### What Is New In v0.5.0

- the PPTX-to-PDF cache is validated against the deck file's modification time: unchanged decks reload instantly from cache, edited decks reconvert automatically
- every external PowerPoint/LibreOffice helper call is now bounded by a timeout, including the PowerPoint `Save As PDF` export fallback that could previously hold the deck loader for up to five minutes if PowerPoint hung on a dialog
- live PowerPoint command safety hardening on the serialized FIFO command path
- expanded audit guardrails so the export timeout and live-command safety rules are checked automatically and regressions fail fast
- refreshed project landing page and a new project case study (`CASESTUDY.md`)
- hardened Windows beta installer and runtime for the separate Windows beta path

### Also Included From Recent Releases

- the live-show path starts the PowerPoint slideshow first, then prepares presenter notes/thumbnails in the background
- clearer OBS source status while presenter assets are still preparing: `live ready, preparing presenter`
- timing logs for live PowerPoint startup, PDF/cache preparation, PDF open time, and notes/media metadata loading
- PowerPoint live mode does not drop out of OBS when an extra next command is sent on the final slide
- live PowerPoint navigation runs on a serialized worker path so rapid commands stay ordered without freezing the OBS interface
- timeout-safe macOS process handling for PowerPoint/LibreOffice helper calls
- `STOP - Stop PowerPoint Live Mode` is asynchronous from source properties
- stale deck registry entries are cleaned up more safely
- release packaging creates only the canonical `pptbridge-obs-macos-apple-silicon.zip` plus checksum
- live builds, animations, and embedded video stay in `PPTBridge SK Slide`
- `PPTBridge SK Presenter` stays lightweight for notes, next slide, timer, and presenter layout customization
- clear `PowerPoint Live Start / Stop` controls are available in the source properties
- Spotlight/Clicker Capture works with common presenter keys: `PageDown` or `Right` for next and `PageUp` or `Left` for previous
- captured clicker keys route to the PPTBridge source in the current OBS program scene and are suppressed from the focused app
- locked PowerPoint resize behavior keeps OBS output stable when the desktop PowerPoint window is made smaller
- OBS can open quietly without immediately launching the PowerPoint slideshow
- `Auto Start PowerPoint When OBS Opens` is available if you prefer automatic startup
- `Close PowerPoint Slideshow When OBS Closes` can clean up the slideshow when OBS quits
- multi-deck live sessions are matched by exact staged PowerPoint file so several PPTX decks can stay open across scenes
- Companion/OSC control, presenter customization, safer OBS-focused hotkeys, and confidence monitor polish remain included

### Basic Setup

1. Download and unzip `pptbridge-obs-macos-apple-silicon.zip`.
2. Open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If OBS is open, quit OBS manually and run the installer again.
5. If macOS blocks the command, right-click it and choose `Open`.
6. Let the installer open OBS.
7. Add `PPTBridge SK Slide` to your program/audience scene.
8. Add `PPTBridge SK Presenter` to your confidence/speaker scene.
9. Select the same `.pptx` or `.pdf` in both sources.
10. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `START - Open PowerPoint / Start Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready.
11. Use `PPTBridge SK Presenter` for notes, next slide, timer, and layout customization. Keep live animations and video in `PPTBridge SK Slide`.

PDF decks do not require PowerPoint. PPTX live mode requires Microsoft PowerPoint for Mac.

### What The Controls Mean

| Control | Meaning |
| --- | --- |
| `START - Open PowerPoint / Start Live Mode` | Starts the PowerPoint slideshow only when you click it |
| `Auto Start PowerPoint When OBS Opens` | Starts PowerPoint automatically when OBS loads the source |
| `Close PowerPoint Slideshow When OBS Closes` | Closes the live slideshow when OBS quits |
| `STOP - Stop PowerPoint Live Mode` | Stops the slideshow without quitting OBS |
| `PowerPoint Resize Behavior` | Locks OBS output size or lets OBS follow the PowerPoint window shape |
| Presenter `PowerPoint Live Start / Stop` | Starts or stops live PowerPoint mode from the presenter source without enabling presenter-side live video capture |
| Multi-deck live matching | Keeps each scene attached to its own `.pptx` even when several PowerPoint slideshows are open |

Default behavior is manual startup. Turn on auto-start only if you want the slideshow to appear as soon as OBS opens.
Default resize behavior is `Lock OBS Output Size`, so shrinking the PowerPoint window on the desktop does not make the OBS program source smaller.

### Slide Control

- OBS hotkeys default to `2` for next slide and `1` for previous slide.
- PPTBridge ignores OBS hotkeys while another app has keyboard focus, so typing elsewhere will not move slides.
- In PowerPoint live mode, extra next commands on the final slide are ignored so the slideshow stays open in OBS at the end of the deck.
- For a Logitech Spotlight or another presenter clicker while the operator uses Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`.
- If macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature again.
- Companion and Stream Deck workflows should use OBS WebSocket or PPTBridge's local OSC listener.
- Local OSC can be enabled in OBS from `Tools > PPTBridge SK: Toggle Local OSC Control`.
- Local OSC listens on `127.0.0.1:57130` and supports `/pptbridge/next`, `/pptbridge/previous`, `/pptbridge/first`, `/pptbridge/last`, `/pptbridge/black`, and `/pptbridge/reload`.

### Included Assets

- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-apple-silicon.zip.sha256`

The demo video stays hosted on the v0.4.7 release and shows the same workflow.

The ZIP includes only the user-facing files needed to install and use the plugin:

- `START-HERE-macOS.txt`
- `1-Install-PPTBridge-SK.command`
- `pptbridge-obs.plugin`
- `README.md`

### Testing Notes

- Apple Silicon was built and runtime-tested locally on OBS Studio 32.1.1 (M1 Pro).
- Runtime testing covered plugin load with zero errors, multi-deck PPTX and PDF loading across scenes, instant cache reloads for unchanged decks, and live OSC verification of every documented path including reload-from-cache.
- The export timeout fix and live-command safety rules are locked in by `tests/audit_guardrails.py`.
- PowerPoint live-mode behavior (final-slide protection, presenter preload) carries over from the v0.4.7 validation.
- Intel stays on the previous beta package until these Apple Silicon changes are separately validated there.
- Windows is not part of this main macOS ZIP release; it remains a separate beta validation path.
