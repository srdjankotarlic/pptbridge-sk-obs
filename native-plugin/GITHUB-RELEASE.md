## PPTBridge SK v0.5.8 - Apple Silicon Stable

PPTBridge SK is a free, independent OBS Studio plugin for live PowerPoint and PDF workflows:

- `PPTBridge SK Slide` gives the audience a clean program output.
- `PPTBridge SK Presenter` gives the speaker or operator current/next slides, notes, timer, and cues.

### Download

Use **`pptbridge-obs-macos-apple-silicon.zip`** for M1/M2/M3/M4 Macs.

Windows x64 and Apple Silicon are stable v0.5.8 platforms. Intel Mac remains a separate beta track. See the [download table](https://github.com/srdjankotarlic/pptbridge-sk-obs#download-and-install) before choosing a package.

### Install

1. Download and unzip `pptbridge-obs-macos-apple-silicon.zip`.
2. Quit OBS and open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If macOS blocks it, right-click the installer and choose `Open`.
5. Let the installer open OBS, then add `PPTBridge SK Slide` or `PPTBridge SK Presenter` from Sources `+`.

For an animated `.pptx`, select the deck and click `Start / Restart PowerPoint Live Mode`. PDF decks render directly and do not require PowerPoint.

### What Is New

- Fixed multi-deck live startup while another PowerPoint slideshow is already running.
- Fixed a render-thread race when Presenter layout or background properties change.
- Added automatic live-session recovery and manual live-window reattach.
- Starting live mode from Presenter now starts the matching Slide source.
- Added clearer validation errors for missing, unsupported, corrupt, or incomplete decks.
- Improved immediate operator/source status refresh after controls are used.
- Expanded embedded-audio cleanup and release QA coverage.
- Kept ordinary left/right arrows free; global clicker capture uses PageDown/PageUp by default.

### Control Options

- Focused OBS hotkeys: `2` next, `1` previous.
- Stage clicker: `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`.
- Companion / Stream Deck: included Generic OSC template and guide.
- Local OSC: commands on `127.0.0.1:57130`, feedback on `57131`.

Controls follow the PPTBridge source in the current OBS Program scene, allowing several decks to stay open without commands going to the wrong presentation.

### Package Contents

- `START-HERE-macOS.txt`
- `1-Install-PPTBridge-SK.command`
- `pptbridge-obs.plugin`
- `README.md`
- `COMPANION-CONTROL.md`
- `companion/PPTBridge-SK-Companion-OSC-Template.json`
- `scripts/send-osc.sh`

The release also includes `pptbridge-obs-macos-apple-silicon.zip.sha256` for checksum verification.

### Verification

The Apple Silicon package was built and runtime-tested on OBS Studio 32.1.1 on an M1 Pro. Coverage included real PPTX/PDF rendering, Presenter layouts, multi-deck routing, PowerPoint live start/stop/navigation/final-slide protection, OSC control and feedback, cue state, cache reuse/invalidation, embedded media audio, isolated installation, sanitizers, static analysis, and release-package checks.

### Help and Demo

- [5-minute quickstart](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/QUICKSTART.md)
- [Full setup guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SETUP-GUIDE.md)
- [Companion / OSC guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/COMPANION-CONTROL.md)
- [FAQ](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md)
- [Support checklist](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SUPPORT.md)
- [2.5-minute silent demo](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov)

PPTBridge SK is a third-party project and is not affiliated with, endorsed by, or maintained by the OBS Project.
