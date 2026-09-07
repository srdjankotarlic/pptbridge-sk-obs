## PPTBridge SK v0.5.12 - Apple Silicon Stable

PPTBridge SK is a free, independent OBS Studio plugin for live PowerPoint and PDF workflows:

- `PPTBridge SK Slide` gives the audience a clean program output.
- `PPTBridge SK Presenter` gives the speaker or operator current/next slides, notes, timer, and cues.

### Download

Use **`pptbridge-obs-macos-apple-silicon.zip`** for M1/M2/M3/M4 Macs.

Apple Silicon v0.5.12 and Windows x64 v0.5.10 are stable platforms. Intel Mac remains a separate beta track. See the [download table](https://github.com/srdjankotarlic/pptbridge-sk-obs#download-and-install) before choosing a package.

### Install

1. Download and unzip `pptbridge-obs-macos-apple-silicon.zip`.
2. Quit OBS and open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If macOS blocks it, right-click the installer and choose `Open`.
5. Let the installer open OBS, then add `PPTBridge SK Slide` or `PPTBridge SK Presenter` from Sources `+`.

For an animated `.pptx`, select the deck and click `Start / Restart PowerPoint Live Mode`. PDF decks render directly and do not require PowerPoint.

**Live capture on macOS:** turn off Stage Manager in `System Settings > Desktop & Dock`
before starting PowerPoint live mode. Otherwise macOS can supply a small thumbnail
or black capture when you switch applications. On macOS 26, use OBS 32.2.2 or newer.
The plugin installer does not update OBS or change Stage Manager for you.

### What Is New

- Verify both the PPTX and cached PDF by content, so replacing a deck at the same path with an older timestamp cannot silently reuse the wrong slides. Damaged or unverified caches are rebuilt.
- Restore the operator's application after preparing the live PowerPoint window, with a bounded activation fallback on newer macOS versions.
- Warn about Stage Manager in live source properties and document the tested workaround.
- Reject PowerPoint temporary lock files (`~$...`) with a useful explanation, show load errors beside Browse, and support OBS missing-file relinking for decks and Presenter backgrounds.
- Let the installer complete successfully without an interactive terminal, while still refusing to replace a plugin in a running OBS instance.
- Keep the existing source names, ordinary Left/Right/Space keys, OSC controls, and minimal Apple Silicon package unchanged.

The first load of a PPTX whose old cache has not been verified exports once after
this update. Later unchanged loads reuse the verified cache. This is a correctness
fix, not a promise of instant conversion for every presentation.

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

Test environment: Apple M1 Pro, macOS 26.6.2, OBS 32.2.2, Microsoft PowerPoint,
Stage Manager off. See the [release QA report](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/qa/MACOS-V0512-RELEASE-QA.md)
for the individual results, earlier failures, and coverage limits. No universal
crash-free guarantee or fresh embedded-media certification is claimed.

The plugin has an ad-hoc signature; it is not Apple Developer ID signed or
notarized. Installation was checked on an existing Mac, not a pristine machine.

### Help and Demo

- [5-minute quickstart](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/QUICKSTART.md)
- [Full setup guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SETUP-GUIDE.md)
- [Companion / OSC guide](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/COMPANION-CONTROL.md)
- [FAQ](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md)
- [Support checklist](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/SUPPORT.md)
- [2.5-minute silent demo](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov)

PPTBridge SK remains free and open source, with no paywall. If it helps your production, optional support is available on [Patreon (suggested $5)](https://www.patreon.com/posts/coffee-158046733).

PPTBridge SK is a third-party project and is not affiliated with, endorsed by, or maintained by the OBS Project.
