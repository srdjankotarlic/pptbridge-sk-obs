# PPTBridge SK for OBS

**PowerPoint and PDF sources for live productions in OBS.**

Created by [Srdjan Kotarlic](https://github.com/srdjankotarlic).

PPTBridge SK adds two native OBS source types:

- `PPTBridge SK Slide` - clean audience/program output
- `PPTBridge SK Presenter` - speaker view with notes, next slide, and timer

[![macOS stable](https://img.shields.io/badge/macOS-v0.2.2_stable-1f6feb?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-supported-000000?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip)
[![Intel Mac](https://img.shields.io/badge/Intel_Mac-supported-555555?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-intel.zip)
[![License](https://img.shields.io/badge/License-see_LICENSE-lightgrey?style=flat-square)](#license)

## Download

| Platform | Status | Download | Notes |
| --- | --- | --- | --- |
| macOS Apple Silicon | Stable | [`pptbridge-obs-macos-apple-silicon.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip) | Use this for M1/M2/M3/M4 Macs |
| macOS Intel | Stable build, needs Intel runtime feedback | [`pptbridge-obs-macos-intel.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-intel.zip) | Use this for older Intel Macs |

The public macOS ZIPs are the safest current path. A signed and notarized `.pkg` installer is tracked for v1.0 in [Issue #1](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/1).

## Install on macOS

1. Download and unzip the ZIP that matches your Mac:
   - Apple Silicon: [`pptbridge-obs-macos-apple-silicon.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip)
   - Intel: [`pptbridge-obs-macos-intel.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-intel.zip)
2. Quit OBS if it is open.
3. Open `START-HERE-macOS.txt`.
4. Double-click `Install-PPTBridge-SK.command`.
5. The installer will copy the plugin and open OBS.
6. Add `PPTBridge SK Slide` or `PPTBridge SK Presenter`.

If macOS blocks the command the first time, right-click it and choose `Open`.

For a fuller walkthrough, see [native-plugin/INSTALL-macOS.md](native-plugin/INSTALL-macOS.md) and [SETUP-GUIDE.md](SETUP-GUIDE.md).

## What It Solves

If you have run PowerPoint in a live show, you know the usual pain: full-screen takeover, awkward window capture, no proper confidence monitor, hotkeys that only work when the right app is focused, and fragile audio routing.

PPTBridge SK is built for conference, church, webinar, keynote, and hybrid-event workflows where the audience feed and speaker monitor should be different.

## Key Features

- **Two native OBS sources** for program output and presenter confidence view.
- **PowerPoint and PDF input** on macOS, including multi-page PDFs.
- **Windowed PowerPoint live mode** so PowerPoint does not take over the desktop.
- **Automatic title-bar crop** for clean live PowerPoint capture.
- **Presenter notes and next-slide preview** from the original deck.
- **Logitech Spotlight-friendly hotkeys** that can work while OBS is in the background.
- **Multi-deck scene routing** so the current program scene controls the right deck.
- **OBS-side audio capture path** for PowerPoint slideshow media.
- **Cached fallback mode** when live PowerPoint mode is unavailable.

## Requirements

| Requirement | macOS stable |
| --- | --- |
| macOS | 12 Monterey or newer |
| CPU | Apple Silicon or Intel |
| OBS Studio | 30 or newer |
| PowerPoint | Microsoft PowerPoint for Mac, required for `.pptx` live mode |
| PDF decks | Supported without PowerPoint |

Apple Silicon was runtime-tested locally on OBS 32.x. Intel is cross-built against the Intel OBS 32.1.2 app and published for community validation on real Intel Macs.

## Screenshots

![PPTBridge SK launch overview](native-plugin/media/github/launch-overview.png)

![PPTBridge SK workflow overview](native-plugin/media/github/workflow-overview.png)

## Release Status

| Release | Status | Use it for |
| --- | --- | --- |
| [`v0.2.2`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.2.2) | macOS stable | Current Apple Silicon + Intel public build with easier installer |
| `v1.0.0` | Planned | Signed/notarized macOS release and wider public launch |

The v1.0 checklist lives in [Issue #1](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/1).

## Documentation

- [SETUP-GUIDE.md](SETUP-GUIDE.md) - user setup and troubleshooting
- [BUILDING.md](BUILDING.md) - developer build commands and dependencies
- [native-plugin/PRO-AUDIO-MODE.md](native-plugin/PRO-AUDIO-MODE.md) - stricter audio routing setups
- [native-plugin/SIGNING-AND-NOTARIZATION.md](native-plugin/SIGNING-AND-NOTARIZATION.md) - v1.0 signing path

## Repository Structure

| Path | Purpose |
| --- | --- |
| `native-plugin/` | Native OBS plugin source, build scripts, release docs |
| `native-plugin/src/` | Native source implementation |
| `native-plugin/scripts/` | Build, packaging, install, signing helpers |
| `native-plugin/media/github/` | GitHub README/release images |
| `pptbridge_obs.py` | Legacy Python MVP kept only for reference |

## Support and Feedback

- For bugs, open a [Bug report](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/new?template=bug_report.md).
- For ideas, open a [Feature request](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/new?template=feature_request.md).
- For v1.0 release progress, follow [Issue #1](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/1).

When reporting a bug, include your macOS version, Mac type, OBS version, PowerPoint version, deck type (`.pptx` or `.pdf`), and the current OBS log.

## Roadmap

- Signed and notarized macOS `.pkg` installer
- Second-Mac clean install verification
- macOS v1.0 OBS Forum release
- More real-machine feedback on Intel Macs

## License

The repo root contains the original project license. The native OBS plugin under `native-plugin/` is distributed as GPL-2.0-or-later because it links against OBS Studio components. See [LICENSE](LICENSE) and [native-plugin/LICENSE](native-plugin/LICENSE).

## Credits

Built by [Srdjan Kotarlic](https://github.com/srdjankotarlic) for real live-production work on stage and in broadcast.
