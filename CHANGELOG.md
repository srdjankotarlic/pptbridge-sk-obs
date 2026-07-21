# Changelog

PPTBridge SK follows separate release tracks for the primary Apple Silicon build and the Intel Mac / Windows beta builds. Download the current packages from the [README](README.md#download-and-install) or [GitHub Releases](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases).

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

## v0.5.8 - Apple Silicon Stable

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
