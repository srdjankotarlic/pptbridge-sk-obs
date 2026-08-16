# PPTBridge SK

**A free OBS Studio plugin that separates clean PowerPoint/PDF slide output for the audience from a customizable presenter view with notes, next slide, and timer.**

Built for and used in real live-event production. PPTBridge SK is an independent third-party plugin and is not affiliated with the OBS Project.

[![Windows v0.5.10 stable](https://img.shields.io/badge/Windows-v0.5.10%20stable-2ea44f)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10) [![macOS Apple Silicon v0.5.8 stable](https://img.shields.io/badge/macOS%20Apple%20Silicon-v0.5.8%20stable-2ea44f)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8) ![OBS Studio 30+](https://img.shields.io/badge/OBS%20Studio-30%2B-4c4c4c)

**[Download Windows x64 v0.5.10](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.10/pptbridge-obs-windows-x64-v0.5.10.zip)** | **[Download macOS Apple Silicon v0.5.8](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.8/pptbridge-obs-macos-apple-silicon.zip)** | [5-minute quickstart](QUICKSTART.md) | [Watch the demo](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov)

[![PPTBridge SK running inside OBS with clean Slide and Presenter sources](native-plugin/media/github/pptbridge-demo-preview.png)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.7/pptbridge-sk-demo.mov)

## Download and Install

Windows x64 and macOS Apple Silicon are stable release platforms. Intel Mac remains a beta track.

| Platform | Download | Status |
| --- | --- | --- |
| Apple Silicon Mac | **[Download v0.5.8 ZIP](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.8/pptbridge-obs-macos-apple-silicon.zip)** | Stable, locally runtime-tested |
| Intel Mac | [Download v0.4.4 ZIP](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip) | Beta |
| Windows 10/11 x64 | **[Download v0.5.10 ZIP](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.10/pptbridge-obs-windows-x64-v0.5.10.zip)** | Stable, runtime-tested PowerPoint and native PDF workflows |

### Install on macOS

1. Download and unzip the ZIP for your Mac.
2. Quit OBS, then open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If macOS blocks it, right-click the installer and choose `Open`.
5. Let the installer copy the plugin and open OBS. Choose normal launch if OBS offers Safe Mode.

The stable ZIP contains only the plugin, installer, start file, user README, Companion guide/template, and OSC helper needed to install and use PPTBridge SK.

### Install on Windows

1. Download and extract the Windows x64 ZIP.
2. Double-click `INSTALL.cmd`.
3. Open OBS Studio 30+. Install desktop Microsoft PowerPoint only if you use PowerPoint files.
4. Add `PPTBridge SK Slide` from the Sources `+` menu.

Windows supports live PowerPoint, native PDF decks, Presenter, animations, embedded media/audio, multiple decks, nested Program-scene clicker routing, resize-safe capture, and legacy `.ppt` files. PDFs open directly through the built-in Windows PDF engine, with no PowerPoint or separate PDF application required.

## Your First Deck

1. Add `PPTBridge SK Slide` to the audience/program scene.
2. Add `PPTBridge SK Presenter` to the stage-monitor or operator scene.
3. Select the same `.pptx` or `.pdf` file in both sources.
4. For animated `.pptx` playback, open either source's properties and click `Start / Restart PowerPoint Live Mode`.
5. Control the deck with OBS hotkeys, source buttons, a stage clicker, Companion, or local OSC.

PDF decks render directly on Windows and macOS and do not require PowerPoint. Desktop Microsoft PowerPoint is required only for PowerPoint files and their live animations, click-builds, video, and audio.

## Two Sources, One Deck

| OBS source | What it shows | Put it here |
| --- | --- | --- |
| `PPTBridge SK Slide` | Clean audience slide output, including live animations/video | Program scene, projector, stream, or recording |
| `PPTBridge SK Presenter` | Current slide, next slide, notes, timer, and cue list | Speaker monitor, confidence monitor, or operator preview |

The presenter view is rendered by PPTBridge inside OBS. It is not a screen capture of PowerPoint Presenter View, so it can be resized, cropped, and customized like a normal OBS source.

## What It Solves

- Keeps the desktop, PowerPoint chrome, and presenter notes out of the audience feed.
- Keeps OBS output stable when the desktop PowerPoint window is moved or resized.
- Shows notes, the next slide, timer, and cues on a separate confidence monitor.
- Loads a static preview first while notes and media metadata finish in the background.
- Supports multiple open decks and routes controls to the deck in the current Program scene.
- Prevents normal typing and left/right arrows from moving slides accidentally.
- Routes supported embedded media audio through the `PPTBridge SK Slide` source.
- Recovers or reattaches a live slideshow without restarting the whole OBS session.

## PowerPoint Live Mode

`PPTBridge SK Slide` and `PPTBridge SK Presenter` expose a highlighted **PowerPoint Live Start / Stop** group when a `.pptx` deck is selected.

| Control | What it does |
| --- | --- |
| `Start / Restart PowerPoint Live Mode` | Opens PowerPoint if needed, starts the slideshow, or recovers a closed live session |
| `Stop PowerPoint Live Mode` | Stops the slideshow without quitting OBS |
| `Auto Start PowerPoint When OBS Opens` | Optionally starts the slideshow when OBS loads the source |
| `Auto Recover Live PowerPoint Session` | Restarts a slideshow that closes unexpectedly after live capture was working |
| `Close PowerPoint Slideshow When OBS Closes` | Optionally cleans up the slideshow when OBS quits |
| `PowerPoint Resize Behavior` | Locks OBS to its canvas or follows the live window shape |
| `Reattach Live PowerPoint Window` | Rebuilds the OBS capture connection without restarting OBS |

Manual startup is the production-safe default. Extra next commands on the final slide are ignored so PowerPoint stays open in OBS at the end of the deck.

## Slide Control

| Method | Best for |
| --- | --- |
| OBS hotkeys | Operator control while OBS is focused |
| Source-property buttons | Setup and quick testing |
| Spotlight/Clicker Capture | A stage remote while the operator works in another app |
| Bitfocus Companion / Stream Deck | Dedicated show-control surfaces |
| Local OSC | Companion, QLab, TouchDesigner, or custom control systems |

Default focused OBS hotkeys are `2` for next and `1` for previous. Normal left/right arrows remain free. PPTBridge ignores those OBS hotkeys while another app has keyboard focus.

For a physical presenter remote, enable `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off`. It captures `PageDown` and `PageUp` by default, routes them to the PPTBridge source in the current Program scene, and leaves ordinary typing keys alone.

Enable local OSC from `Tools > PPTBridge SK: Local OSC Control On/Off`. Commands listen on `127.0.0.1:57130`:

- `/pptbridge/next`
- `/pptbridge/previous`
- `/pptbridge/first`
- `/pptbridge/last`
- `/pptbridge/black`
- `/pptbridge/reload`

OSC feedback can report current/total slide, titles, timer, deck/file/source names, loading or error state, live status, black-screen state, and cue checked state on port `57131`. A ready-to-import Generic OSC template is included in the package and repository.

## Multiple Decks

Create one OBS scene per deck and add that deck's Slide/Presenter sources to it. Start each `.pptx` you want ready, then switch Program scenes during the show. Hotkeys, OSC, and clicker capture follow the PPTBridge source in the current Program scene, not whichever source happened to render last.

## Presenter Customization

`PPTBridge SK Presenter` includes:

- balanced, large-preview, large-notes, compact, and confidence-monitor layouts
- preview fit, fill, crop, scale, and position
- notes font size, zoom, area size, and vertical position
- background color and optional background image/logo
- fit, fill, or watermark background placement
- cue-list display, check/uncheck controls, and `.txt` export

Live animation and embedded video remain in `PPTBridge SK Slide`; Presenter stays a lightweight confidence view for stability.

## Requirements

| Requirement | Apple Silicon stable | Intel Mac beta | Windows stable |
| --- | --- | --- | --- |
| OS | macOS 12+ | macOS 12+ | Windows 10/11 x64 |
| OBS Studio | 30+ | 30+ | 30+ |
| PowerPoint | Required for live `.pptx` | Required for live `.pptx` | Required for PowerPoint files; not for PDF |
| PDF decks | Supported without PowerPoint | Supported without PowerPoint | Supported without PowerPoint |

The Apple Silicon build is runtime-tested on OBS Studio 32.1.1 on an M1 Pro with real PPTX/PDF decks, multi-deck routing, live start/stop/navigation, Presenter layouts, OSC feedback, cue state, cache behavior, embedded media audio, isolated installation, and release-package checks.

The Windows stable build is runtime-tested on Windows 11 x64 with OBS Studio 32.1.2 using native PDF decks plus desktop PowerPoint 2010 for animations, notes, embedded video/audio, Spotlight-style `PageDown`/`PageUp` clicker input, OSC, nested Program/Preview isolation, multiple simultaneous and same-named decks, legacy `.ppt`, real event decks, repeated Start/Stop cycles, a media-heavy 8 GB deck, PDF concurrency, cache recovery, and installer rollback. The Windows DLL and installer are not code-signed yet, so Windows may ask for confirmation. Rehearse every event deck on the production PC before show day.

## Documentation and Help

| Need | Guide |
| --- | --- |
| Fastest setup | [QUICKSTART.md](QUICKSTART.md) |
| Full setup and troubleshooting | [SETUP-GUIDE.md](SETUP-GUIDE.md) |
| Common questions | [FAQ.md](FAQ.md) |
| macOS installation details | [native-plugin/INSTALL-macOS.md](native-plugin/INSTALL-macOS.md) |
| Windows installation | [native-plugin/INSTALL-Windows.md](native-plugin/INSTALL-Windows.md) |
| Companion / Stream Deck / OSC | [native-plugin/COMPANION-CONTROL.md](native-plugin/COMPANION-CONTROL.md) |
| Companion starter template | [PPTBridge-SK-Companion-OSC-Template.json](native-plugin/companion/PPTBridge-SK-Companion-OSC-Template.json) |
| Audio routing | [native-plugin/PRO-AUDIO-MODE.md](native-plugin/PRO-AUDIO-MODE.md) |
| Report a problem | [SUPPORT.md](SUPPORT.md) |
| Build or contribute | [CONTRIBUTING.md](CONTRIBUTING.md) / [BUILDING.md](BUILDING.md) |

Before reporting a bug, check [SUPPORT.md](SUPPORT.md). Include the OS, CPU/Mac type, OBS/PPTBridge/PowerPoint versions, deck type, what you expected, and the OBS log from `Help > Log Files > View Current Log`.

Use [GitHub Discussions](https://github.com/srdjankotarlic/pptbridge-sk-obs/discussions) for setup questions, workflow ideas, and general feedback. Use [GitHub Issues](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues) for reproducible bugs and feature requests.

## Releases

The current stable releases are **[v0.5.10 for Windows x64](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10)** and **[v0.5.8 for Apple Silicon](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8)**. Choose the ZIP that matches your operating system.

See [CHANGELOG.md](CHANGELOG.md) for release history and [all GitHub releases](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases) for older and beta packages.

## Repository Structure

| Path | Purpose |
| --- | --- |
| `native-plugin/` | Native plugin source, build scripts, release docs, media, and packaging helpers |
| `native-plugin/src/` | C++, Objective-C++, and Windows backend source |
| `native-plugin/companion/` | Companion / Generic OSC starter template |
| `native-plugin/scripts/` | Build, packaging, install, OSC, signing, and cleanup helpers |
| `docs/` | Static project website and discovery metadata |
| `pptbridge_obs.py` | Legacy Python MVP kept for historical reference |

## Roadmap

- Signed and notarized macOS installer
- More real Intel Mac and Windows live-production validation
- Code-signed Windows installer
- Companion preset import/export polish across Companion versions
- Video remaining-time support where PowerPoint/media state can be read reliably

## Support the Project

PPTBridge SK stays free and open source. A [GitHub star](https://github.com/srdjankotarlic/pptbridge-sk-obs), a real-world test report, or sharing it with another AV operator helps the project grow. Optional support is available on [Patreon](https://www.patreon.com/posts/coffee-158046733).

## License

The repo root contains the original project license. The native plugin under `native-plugin/` is distributed as GPL-2.0-or-later because it links against OBS Studio components. See [LICENSE](LICENSE) and [native-plugin/LICENSE](native-plugin/LICENSE).

## Credits

Built by [Srdjan Kotarlic](https://github.com/srdjankotarlic) for real live-production work on stage and in broadcast.
