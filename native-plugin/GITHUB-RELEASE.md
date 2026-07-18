## PPTBridge SK for OBS v0.5.8

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
| Apple Silicon Mac | `pptbridge-obs-macos-apple-silicon.zip` | Stable |
| Older Intel Mac | Use v0.4.4 `pptbridge-obs-macos-intel.zip` | Beta |

Apple Silicon is the main stable build. Intel Mac and Windows remain separate beta paths while real-hardware feedback is collected.

### What Is New In v0.5.8

- Fixed multi-deck live startup on macOS: presentations now open through LaunchServices, avoiding PowerPoint's hidden `Grant File Access` dialog while another slideshow is running.
- Fixed an OBS render-thread race that could freeze OBS when Presenter layout, background image, or other non-size properties were changed during preview.
- Added `Auto Recover Live PowerPoint Session`. After live capture has worked, PPTBridge restarts a slideshow that closes unexpectedly; an intentional Stop remains stopped.
- Added `Reattach Live PowerPoint Window` and hardened live-window discovery, capture recreation, and frame watchdog behavior.
- Starting live mode from a matching Presenter source now enables and starts the corresponding Slide source, so the animated audience output is not left in static mode.
- Missing, unsupported, corrupt, and incomplete `.pptx`/`.pdf` inputs are rejected early with a clear source status instead of entering a confusing loading state.
- Fixed operator controls so both the Show Control status and lower Source Status refresh immediately after navigation, black-screen, reload, live, and cue-check actions.
- Verified embedded WAV/MP3 audio routing through `PPTBridge SK Slide`: media populates the source meter and honors source gain/mute without double mixing. The optional live PowerPoint app-audio path remains permission- and deck-dependent and should be tested on the show computer.
- Added dedicated lifecycle cleanup for private media and app-audio capture callbacks.
- Expanded release QA coverage for invalid input, registry behavior, OSC control/feedback, multi-live workflows, 15-deck rendering, embedded audio, real OBS runtime, sanitizers, static analysis, cache behavior, packaging, and isolated installation.
- Corrected clicker documentation: global capture uses PageDown/PageUp by default and deliberately leaves plain typing keys and normal left/right arrows available.

### Also Included From v0.5.7

- Hardened the PowerPoint AppleScript runner used by live mode and the PowerPoint Save As PDF fallback.
- Fixed a non-ARC task-output lifetime bug that could crash PPTX loading while reading helper-process stdout/stderr.
- Fixed idle PowerPoint retry detection so a stuck empty PowerPoint session can be restarted and retried instead of leaving Start Live looking idle.
- If PPTBridge launches PowerPoint and that fresh launch becomes unresponsive during Start Live, it can now terminate that owned launch and retry without touching a PowerPoint session that was already open before the attempt.
- Live mode opens the original selected `.pptx` first and uses the staged deck copy only as a fallback.
- Presenter view gives a clearer manual-live-mode message instead of looking like a stalled conversion when live mode is enabled but not started.

### Also Included From v0.5.6

- Fixed `Start / Restart PowerPoint Live Mode` when clicked immediately after a fast preview appears but notes/media are still preparing.
- PowerPoint live-mode staging now uses a PowerPoint-readable temp folder instead of the OBS/Application Support cache path, avoiding macOS PowerPoint automation failures when opening staged decks.
- If PowerPoint is running but idle and stuck after a failed live-start attempt, PPTBridge now restarts idle PowerPoint and retries once.
- PDF decks now hide PowerPoint Live Mode controls and show a clear note that PDFs are rendered and controlled directly by PPTBridge.
- Added a live PowerPoint smoke test that verifies manual preview, live start, and live stop.

### Also Included From v0.5.5

- Faster first preview when a PPTX or PDF deck is loaded in OBS.
- PPTBridge now publishes a renderable static preview as soon as the generated or cached PDF opens.
- Presenter notes, slide titles, embedded media metadata, and cue details continue preparing in the background instead of blocking the first visible slide.
- OBS log timing now clearly separates static preview open time from notes/media preparation time.
- Audit guardrails now fail if deck loading regresses to waiting for slow notes/media extraction before the first preview can render.

### Also Included From v0.5.4

- Default OBS hotkeys now use `2` for next slide and `1` for previous slide.
- Existing old defaults that included `Right Arrow` and `Left Arrow` are migrated to `2`/`1` on launch.
- Spotlight/Clicker Capture defaults now use `PageDown` and `PageUp` only, so normal left/right arrows remain available for OBS controls, text fields, and other apps.
- README, Quickstart, macOS install docs, packaged README, and Companion guide updated to match the safer keyboard behavior.
- Audit guardrails now fail if plain left/right arrows are reintroduced as default global controls.

### Also Included From v0.5.3

- Companion OSC starter template included in the package
- expanded OSC feedback for show-control workflows
- packaging polish for the Apple Silicon ZIP

### Also Included From v0.5.2

- New `Show Control (Operator Mode)` group near the top of source properties, with the practical show buttons in one place
- Interactive cue buttons: check/uncheck current cue, check/uncheck next cue, and clear checked cues
- OSC status feedback for Companion, QLab, TouchDesigner, or another local show-control tool
- Status paths include current slide, total slides, current title, next title, timer, live-ready state, and black-screen state
- OBS Tools menu labels are clearer: `Local OSC Control On/Off` and `Spotlight/Clicker Capture On/Off`
- Install docs, Quickstart, Companion guide, and packaged README were updated to match the current controls

### Also Included From v0.5.1 And Recent Releases

- `Start / Restart PowerPoint Live Mode` recovers more clearly when the slideshow window was closed while PowerPoint is still open
- default focused OBS hotkeys now use `2` for next and `1` for previous so normal left/right arrows stay available
- `PPTBridge SK Presenter` supports presenter background color, optional background image/logo placement, opacity, and fit/fill/watermark modes
- `PPTBridge SK Presenter` can show a compact cue list and export that cue list as a `.txt` file from source properties

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
- `Stop PowerPoint Live Mode` is asynchronous from source properties
- stale deck registry entries are cleaned up more safely
- release packaging creates only the canonical `pptbridge-obs-macos-apple-silicon.zip` plus checksum
- live builds, animations, and embedded video stay in `PPTBridge SK Slide`
- `PPTBridge SK Presenter` stays lightweight for notes, next slide, timer, and presenter layout customization
- clear `PowerPoint Live Start / Stop` controls are available in the source properties
- Spotlight/Clicker Capture works with common presenter keys: `PageDown` for next and `PageUp` for previous by default
- captured clicker keys route to the PPTBridge source in the current OBS program scene and are suppressed from the focused app
- locked PowerPoint resize behavior keeps OBS output stable when the desktop PowerPoint window is made smaller
- OBS can open quietly without immediately launching the PowerPoint slideshow
- `Auto Start PowerPoint When OBS Opens` is available if you prefer automatic startup
- `Close PowerPoint Slideshow When OBS Closes` can clean up the slideshow when OBS quits
- multi-deck live sessions are matched by the exact selected PowerPoint path (or its fallback copy) so several PPTX decks can stay open across scenes
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
10. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `Start / Restart PowerPoint Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready.
11. Use `PPTBridge SK Presenter` for notes, next slide, timer, and layout customization. Keep live animations and video in `PPTBridge SK Slide`.

PDF decks do not require PowerPoint. PPTX live mode requires Microsoft PowerPoint for Mac.

### What The Controls Mean

| Control | Meaning |
| --- | --- |
| `Start / Restart PowerPoint Live Mode` | Opens PowerPoint if needed, starts the slideshow only when you click it, and recovers if the slideshow window was closed |
| `Auto Start PowerPoint When OBS Opens` | Starts PowerPoint automatically when OBS loads the source |
| `Close PowerPoint Slideshow When OBS Closes` | Closes the live slideshow when OBS quits |
| `Stop PowerPoint Live Mode` | Stops the slideshow without quitting OBS |
| `PowerPoint Resize Behavior` | Locks OBS output size or lets OBS follow the PowerPoint window shape |
| Presenter `PowerPoint Live Start / Stop` | Starts or stops live PowerPoint mode from the presenter source without enabling presenter-side live video capture |
| Multi-deck live matching | Keeps each scene attached to its own `.pptx` even when several PowerPoint slideshows are open |

Default behavior is manual startup. Turn on auto-start only if you want the slideshow to appear as soon as OBS opens.
Default resize behavior is `Lock OBS Output Size`, so shrinking the PowerPoint window on the desktop does not make the OBS program source smaller.

### Slide Control

- OBS hotkeys default to `2` for next slide and `1` for previous slide. Normal left/right arrows stay free.
- PPTBridge ignores OBS hotkeys while another app has keyboard focus, so typing elsewhere will not move slides.
- In PowerPoint live mode, extra next commands on the final slide are ignored so the slideshow stays open in OBS at the end of the deck.
- For a Logitech Spotlight or another presenter clicker while the operator uses Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`.
- If macOS asks, allow OBS in `System Settings > Privacy & Security > Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature again.
- Companion and Stream Deck workflows should use OBS WebSocket or PPTBridge's local OSC listener.
- Local OSC can be enabled in OBS from `Tools > PPTBridge SK: Local OSC Control On/Off`.
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
- `COMPANION-CONTROL.md`
- `companion/PPTBridge-SK-Companion-OSC-Template.json`
- `scripts/send-osc.sh`

### Testing Notes

- Apple Silicon was built and runtime-tested locally on OBS Studio 32.1.1 (M1 Pro).
- Runtime testing covered plugin load, real PPTX/PDF rendering, Presenter layouts, multi-deck Program-scene routing, PowerPoint live start/stop/navigation/black/final-slide protection, OSC control/feedback, cue state, cache reuse/invalidation, and source-property status refresh.
- Audio testing covered embedded WAV and MP3 media, OBS source meter output, recording, mute, exact gain adjustment, repeated source lifecycle, and shutdown/restart behavior.
- Automated release gates covered 15 real/synthetic presentations, invalid files, two simultaneous live decks, AddressSanitizer/UndefinedBehaviorSanitizer, Clang static analysis, packaging contents, code architecture, and an isolated-home installer run.
- `tests/audit_guardrails.py` locks in the process-timeout, live-command, hotkey, loading, and lifecycle safety rules.
- Intel stays on the previous beta package until these Apple Silicon changes are separately validated there.
- Windows is not part of this main macOS ZIP release; it remains a separate beta validation path.
