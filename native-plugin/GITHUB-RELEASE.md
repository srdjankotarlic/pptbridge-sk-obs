## PPTBridge SK v0.5.11 - Apple Silicon Stable

PPTBridge SK is a free, independent OBS Studio plugin for live PowerPoint and PDF workflows:

- `PPTBridge SK Slide` gives the audience a clean program output.
- `PPTBridge SK Presenter` gives the speaker or operator current/next slides, notes, timer, and cues.

### Download

Use **`pptbridge-obs-macos-apple-silicon.zip`** for M1/M2/M3/M4 Macs.

Apple Silicon v0.5.11 and Windows x64 v0.5.10 are stable platforms. Intel Mac remains a separate beta track. See the [download table](https://github.com/srdjankotarlic/pptbridge-sk-obs#download-and-install) before choosing a package.

### Install

1. Download and unzip `pptbridge-obs-macos-apple-silicon.zip`.
2. Quit OBS and open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If macOS blocks it, right-click the installer and choose `Open`.
5. Let the installer open OBS, then add `PPTBridge SK Slide` or `PPTBridge SK Presenter` from Sources `+`.

For an animated `.pptx`, select the deck and click `Start / Restart PowerPoint Live Mode`. PDF decks render directly and do not require PowerPoint.

### What Is New

- Updated Apple Silicon to the current shared PPTBridge codebase.
- Added routing through nested OBS scenes and groups, so controls keep following the Program deck.
- Hardened Presenter source teardown and removed stale render-state cleanup code.
- Expanded repeatable OBS tests for real PPTX/PDF decks, live PowerPoint, Presenter layouts, OSC/Companion feedback, cue state, clicker isolation, and embedded-media audio.
- Kept ordinary Left/Right/Space keys free; global clicker capture uses PageDown/PageUp by default.
- Kept the download minimal: one Apple Silicon ZIP, checksum, double-click installer, and only the files needed to install and operate the plugin.

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

The Apple Silicon package was built and runtime-tested on OBS Studio 32.1.1 on an M1 Pro. Coverage included real PPTX/PDF rendering, Presenter layouts, nested and multi-deck Program routing, PowerPoint live start/stop/restart/navigation/final-slide protection/black screen/reattach, all OSC controls and 16 feedback fields, cue state, cache reuse, embedded-media audio gain/disable, isolated installation, sanitizers, and release-package checks.

### Help and Demo

- [5-minute quickstart](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/QUICKSTART.md)
- [Full setup guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SETUP-GUIDE.md)
- [Companion / OSC guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/COMPANION-CONTROL.md)
- [FAQ](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md)
- [Support checklist](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SUPPORT.md)
- [2.5-minute silent demo](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov)

PPTBridge SK remains free and open source, with no paywall. If it helps your production, optional support is available on [Patreon (suggested $5)](https://www.patreon.com/posts/coffee-158046733).

PPTBridge SK is a third-party project and is not affiliated with, endorsed by, or maintained by the OBS Project.
