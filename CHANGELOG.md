# Changelog

PPTBridge SK v0.5.11 is the current stable Apple Silicon release. Windows x64 remains stable on v0.5.10, with Intel Mac on a separate beta track. Download the current packages from the [README](README.md#download-and-install) or [GitHub Releases](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases).

## macOS v0.5.11 - Apple Silicon Validation and Routing Hardening

- Updated the Apple Silicon package to the current shared PPTBridge codebase.
- Added nested Program-scene routing so hotkeys, clicker input, and OSC find the correct deck inside nested OBS scenes and groups.
- Hardened Presenter source teardown and removed stale render-state cleanup code.
- Revalidated real PPTX/PDF loading, cached reloads, Presenter layouts, two-deck routing, live start/stop/restart, final-slide protection, black screen, and live-window reattach in OBS 32.1.1.
- Revalidated all OSC controls and 16 feedback fields, cue state/export, PageUp/PageDown clicker routing, ordinary Left/Right/Space keyboard input, and embedded-media audio gain/disable behavior.
- Expanded the repeatable macOS runtime suite and fixed QA timing/decode assumptions that could falsely report failures on slower first loads or media slides.
- Kept the release package minimal: one Apple Silicon ZIP, one checksum, and the double-click installer.

[Apple Silicon v0.5.11 release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.11)

## Windows v0.5.10 - Production Hardening

- Fixed intermittent blank white live frames by requiring OBS Window Capture to be fully hooked before replacing the last good slide.
- Isolated live PowerPoint windows by exact canonical file path, including two different decks that share the same filename.
- Routed clicker, OSC, and PowerPoint audio correctly through nested OBS scenes while preserving Program/Preview isolation.
- Added transactional PowerPoint/PDF caches, active-use leases, bounded retention, junction-safe cleanup, and strict embedded-media size/free-space limits.
- Serialized native PDF rendering across OBS processes to prevent a Windows GPU-driver access violation found during parallel stress testing.
- Made `INSTALL.cmd` transactional: new files are staged and hashed first, failed activation restores the previous plugin, invalid paths never fall back to another OBS copy, and hash verification no longer depends on optional PowerShell modules.
- Expanded release QA to cover real event decks, an 8 GB media deck, animation pixel validation, same-name decks, nested scenes, multiple simultaneous PowerPoint/PDF sources, PDF corruption/recovery/concurrency, repeated lifecycle runs, resource plateau, and negative installer paths.
- Kept the Windows download to exactly five user-facing files with the same extract-and-double-click workflow.

[Windows v0.5.10 release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10)

## Windows v0.5.9 - Stable PDF Support

- Added native PDF page rendering through the built-in Windows PDF engine; no PowerPoint or separate PDF application is required for PDF decks.
- Reused the existing Slide, Presenter, source buttons, final-page guard, black screen, Program-scene clicker routing, OBS hotkeys, and OSC controls for PDFs.
- Added PDF cache reuse, multiple simultaneous PDF decks, and PDF/PowerPoint coexistence.
- Kept PowerPoint-only controls hidden and disabled for PDFs so setup remains clear.
- Added standalone renderer checks and real OBS runtime coverage for valid multi-page PDFs, corrupted PDF rejection, navigation, Presenter, exact page counts, caching, clicker-style input, and OSC.
- Kept the Windows download to five files with the same double-click `INSTALL.cmd` workflow.

[Windows v0.5.9 release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.9)

## Windows v0.5.8 - Stable

- Promoted the runtime-tested Windows PowerPoint plugin to the stable v0.5.8 release alongside Apple Silicon.
- Added the minimal five-file Windows ZIP with a double-click installer, plugin DLL, short user guide, and two required locale files.
- Fixed the administrator-permission launcher used by `INSTALL.cmd` for normal OBS installations under `Program Files`.
- Replaced the fragile PowerShell `Start-Process` elevation path with Windows ShellExecute `runas`, including a clear message when UAC permission is cancelled.
- Validated Slide, Presenter, animations, audio/video, resize, final-slide protection, Program-scene clicker routing, multiple decks, OSC, recovery, legacy `.ppt`, invalid input safety, and repeated Start/Stop stress in real OBS.

[Windows stable release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8)

## v0.5.8-windows-beta.1 - Windows x64 Beta

- Added clean live PowerPoint capture without PowerPoint chrome, desktop, scrollbars, or resize artifacts.
- Added reliable `.pptx` and legacy binary `.ppt` export/live handling, including localized PowerPoint image names.
- Added Presenter parity: notes, next slide, timer, cue list, five layouts, preview scaling, and custom backgrounds.
- Added live animations, click builds, embedded video, PowerPoint process audio, and OBS mixer gain/mute control.
- Added canonical multi-deck routing, queued Start, generation-safe Start/Stop/Restart, reattach, and automatic recovery.
- Added final-slide protection so extra Next presses keep the slideshow open and Previous can return.
- Added Program-scene Spotlight/PageDown/PageUp capture while ordinary keyboard input remains available to the operator.
- Isolated process audio to the current Program scene so hidden and Studio Preview sources do not create duplicate loopback clients.
- Added fast live startup for very large media decks without copying embedded videos into the cache.
- Added a five-file Windows ZIP with a double-click installer that detects normal, portable, and custom OBS installations.
- Added Windows runtime QA for OBS source registration, Presenter rendering, audio/video, clicker/OSC, invalid files, multiple decks, legacy decks, and repeated Start/Stop stress.

[Windows beta release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8-windows-beta.1)

## macOS v0.5.8 - Apple Silicon Stable

- Fixed multi-deck live startup when another PowerPoint slideshow is already running.
- Fixed a render-thread race when changing Presenter layout and background properties.
- Added automatic live-session recovery and manual live-window reattach.
- Starting live mode from Presenter now starts the matching Slide source.
- Added early validation and clearer errors for missing, unsupported, corrupt, or incomplete decks.
- Improved immediate operator/source status refresh after controls are used.
- Expanded embedded-audio cleanup and release QA coverage.
- Kept normal left/right arrows free and documented PageDown/PageUp clicker capture correctly.

[Release notes and download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8)

## Release History

| Release | Track | Main focus |
| --- | --- | --- |
| [v0.5.11](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.11) | Apple Silicon stable | Nested Program-scene routing, Presenter teardown hardening, full Mac runtime regression, and minimal installer package |
| [v0.5.10](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10) | Windows x64 stable | Live-capture, nested-scene, same-name deck, cache, concurrent PDF, and installer hardening |
| [v0.5.9](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.9) | Windows x64 stable | Native PDF support without PowerPoint, plus existing live PowerPoint, Presenter, clicker/OSC, and easy installer |
| [v0.5.8](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8) | Windows x64 and Apple Silicon stable | Live PowerPoint/PDF platform workflows, Presenter, clicker/OSC, audio, recovery, and easy installers |
| [v0.5.8-windows-beta.1](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.8-windows-beta.1) | Windows beta | Live capture, Presenter parity, Program-scene clicker/audio routing, multi-deck stability, and easy installer |
| [v0.5.7](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.7) | Previous Apple Silicon stable | PowerPoint automation, Start Live regression tests, and cue-list smoke coverage |
| [v0.5.6](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.6) | Previous Apple Silicon stable | Start Live reliability, PDF control clarity, and readable live staging |
| [v0.5.5](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.5) | Previous Apple Silicon stable | Faster first preview while notes/media prepare in the background |
| [v0.5.4](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.4) | Previous Apple Silicon stable | Safer hotkey defaults; normal left/right arrows remain free |
| [v0.5.3](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.3) | Previous Apple Silicon stable | Companion template, OSC feedback, and packaging polish |
| [v0.5.2](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.2) | Previous Apple Silicon stable | Operator controls, cue checks, status feedback, and clearer menus |
| [v0.5.1](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.1) | Previous Apple Silicon stable | Restart recovery, Presenter backgrounds, and cue-list display/export |
| [v0.5.0](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.0) | Previous Apple Silicon stable | Cache validation and bounded PowerPoint helper timeouts |
| [v0.5.0-beta.1](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.0-beta.1) | Windows beta | Windows x64 PowerPoint live-mode installer |
| [v0.4.7](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.7) | Previous Apple Silicon stable | Faster Presenter preparation and final-slide live protection |
| [v0.4.6](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.6) | Previous Apple Silicon stable | Live-control stability and safer process handling |
| [v0.4.5](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.5) | Previous Apple Silicon stable | Presenter stability, clearer controls, and clean packaging |
| [v0.4.4](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.4) | Intel Mac beta | Current separate Intel Mac package |
| [v0.4.3](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.3) | Previous Apple Silicon stable | Default Presenter clicker capture |
| [v0.4.2](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.2) | Previous Apple Silicon stable | Spotlight/clicker capture and manual PowerPoint lifecycle controls |
| [v0.4.1](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.1) | Previous stable | Manual PowerPoint lifecycle controls |
| [v0.4.0](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.4.0) | Previous stable | Companion/OSC and Presenter customization |
| [v0.3.0](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.3.0) | Previous stable | Presenter customization and confidence-monitor polish |
| [v0.2.2](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.2.2) | Previous stable | First separate Apple Silicon and Intel public builds |

For complete technical detail, open the matching release page in [GitHub Releases](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases).
