# PPTBridge SK for OBS

**Created by Srdjan Kotarlic**

PPTBridge SK is a native **macOS-first** OBS plugin for PowerPoint and PDF workflows in live production. It turns any `.pptx` or `.pdf` into two clean OBS sources — one for the audience program feed, one for the presenter's confidence monitor — and gives the speaker a clicker that actually works.

[![macOS stable](https://img.shields.io/badge/macOS-v0.2.0_stable-1f6feb?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-000000?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest)
[![Download macOS plugin](https://img.shields.io/badge/Download-macOS_plugin-2da44e?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-arm64.zip)
[![Windows](https://img.shields.io/badge/Windows-beta_preview-6f42c1?style=flat-square)](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.2.0-beta1)
[![License](https://img.shields.io/badge/License-see_LICENSE-lightgrey?style=flat-square)](LICENSE)

## Download

| Platform | Status | What to download | Link |
| --- | --- | --- | --- |
| macOS (Apple Silicon) | **Stable** | `pptbridge-obs-macos-arm64.zip` | [Download macOS stable](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-arm64.zip) |
| Windows | **Beta preview** | `PPTBridge-SK-for-OBS-Installer-v0.1.4.zip` | [Open Windows beta release](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.2.0-beta1) |

> **If you want the stable public build, download the macOS release.**
>
> The Windows release is still a beta preview for testing and feedback.

Unzip and drop `pptbridge-obs.plugin` into:

```
~/Library/Application Support/obs-studio/plugins/
```

Restart OBS. That's it.

## Why PPTBridge SK

If you have ever run a live show with PowerPoint, you know the pain — slides either take over the whole desktop, audio doesn't route, the presenter has no confidence view, and a clicker only works if OBS is focused. PPTBridge SK fixes all of that in a single plugin, built from the ground up for live production on macOS.

- **Two purpose-built sources** — `PPTBridge SK Slide` for a clean program feed, `PPTBridge SK Presenter` for stage monitors with notes, next-slide preview, and timer.
- **Point it at a file, you're done** — works with `.pptx` and, as of v0.2.0, multi-page `.pdf` as a native slide source (no PowerPoint needed for PDFs).
- **Clicker that actually clicks** — Logitech Spotlight, Kensington, generic USB presenters, or any OBS hotkey. Works with OBS in the background — the presenter can move slides from the stage without ever touching the production laptop.
- **PowerPoint stays windowed** — slideshow runs in a window, so the operator keeps full access to OBS and the rest of macOS during the show. The title bar is automatically cropped out of the program feed.
- **Multiple decks, one show** — run several presentations in parallel, each on its own scene. Hotkeys automatically route to whichever deck is in the current program scene. No re-focusing, no juggling.
- **Audio routing built in** — PowerPoint slideshow audio is captured and routed into the OBS mixer, with app-level audio capture in live mode and a built-in gain trim.
- **Safe fallback** — if live PowerPoint mode is unavailable for any reason, the plugin falls back to a cached render so the show never stops.

## Best Fit

PPTBridge SK is used in:

- conferences and corporate events
- church livestreams
- webinars and online summits
- keynote-style stage production
- hybrid events with confidence monitors
- any live workflow that mixes PowerPoint, PDF handouts, and OBS

## Preview

![PPTBridge SK launch overview](native-plugin/media/github/launch-overview.png)

![PPTBridge SK workflow overview](native-plugin/media/github/workflow-overview.png)

## What's New in v0.2.0 (Pro-Live macOS)

- **Multi-deck scene routing.** Put a different deck on every scene. Spotlight / hotkey presses automatically target the deck in the current program scene, with a fallback to the last active deck for single-deck shows.
- **PDF as a native slide source.** Drop a multi-page PDF into a `PPTBridge SK Slide` source — no PowerPoint conversion step, no intermediate export. Great for handouts, keynote exports, and speakers who bring PDFs.
- **Logitech Spotlight + background hotkeys.** Defaults wired for `PageDown` / `PageUp` / `Right` / `Left` / `Space` (next/previous), `B` (black screen), `Home` (first), `End` (last). All active even when OBS is not in focus — no interference with the rest of macOS.
- **Windowed PowerPoint slideshow.** PowerPoint no longer takes over the whole screen. The operator keeps full use of OBS, chat, and macOS itself during the show.
- **Automatic title-bar crop.** The "PowerPoint Slide Show – …" chrome that macOS adds to a windowed slideshow is cropped out of the program feed with an internal `crop_filter`, so the audience only sees the slide.
- **macOS 26 (Tahoe) TCC fix.** Deck cache moved to `~/Library/Application Support/PPTBridge SK/cache/...` so the plugin is not blocked by Tahoe's cross-container sandbox rules.
- **Live-session fast path.** If PowerPoint is already running the current deck in slideshow, PPTBridge attaches to it instantly instead of restarting playback.

See the full [release notes](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest) for details.

## Which Release Is Which

- `v0.2.0` = **macOS stable**
- `v0.2.0-beta1` = **Windows beta preview**
- If you are just trying the plugin and want the safest current path, use the macOS stable release.

## Quick Start

1. Download the plugin zip above and copy `pptbridge-obs.plugin` into `~/Library/Application Support/obs-studio/plugins/`.
2. Restart OBS.
3. Grant Screen Recording and Accessibility permissions the first time OBS and Microsoft PowerPoint ask — this is what lets PPTBridge capture the slideshow window and drive the clicker.
4. In OBS, add `PPTBridge SK Slide` to your program scene and `PPTBridge SK Presenter` to your stage / confidence monitor scene.
5. Point both sources to the same `.pptx` or `.pdf`.
6. Open `Settings > Hotkeys` and accept the PPTBridge defaults, or bind your own clicker keys.

For a room-by-room walkthrough, see [SETUP-GUIDE.md](SETUP-GUIDE.md).

## Requirements

- macOS 12 Monterey or newer (tested on macOS 15 Sequoia and macOS 26 Tahoe)
- Apple Silicon (arm64). Intel Mac universal builds on request — open an issue.
- OBS Studio 30 or newer
- Microsoft PowerPoint for Mac (only needed for `.pptx` live mode; PDFs work standalone)
- A presenter remote is optional — the plugin works perfectly from the OBS hotkey panel alone

## Roadmap

- Universal (arm64 + x86_64) macOS build
- Windows stable release — the beta preview is live at [`v0.2.0-beta1`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.2.0-beta1)
- Native PDF rendering on Windows (currently macOS-only)
- Keynote `.key` as a native source

## Repo Structure

- [native-plugin](native-plugin) — native plugin source, build scripts, installers
- [BUILDING.md](BUILDING.md) — developer build commands and dependencies
- [SETUP-GUIDE.md](SETUP-GUIDE.md) — end-user setup walkthrough
- [install_deps.sh](install_deps.sh) — developer dependency helper
- [pptbridge_obs.py](pptbridge_obs.py) — legacy Python MVP kept for reference

## Notes for Production

- `PPTBridge SK Slide` prefers true live PowerPoint mode — it preserves PowerPoint builds, animations, transitions, and embedded media exactly as the audience would see them locally.
- `PPTBridge SK Presenter` is a custom presenter layout synchronized to the deck, driven by PPTX notes pages and slide thumbnails. Notes appear only when the source deck actually contains notes.
- If you need tight OBS-side control over local PowerPoint audio during a show, see the virtual routing guide in [`native-plugin/PRO-AUDIO-MODE.md`](native-plugin/PRO-AUDIO-MODE.md).
- Public product direction is the native `PPTBridge SK for OBS` plugin. The Python MVP in the repo root is kept only as historical reference.

## Credits

Built by [Srdjan Kotarlic](https://github.com/srdjankotarlic) for real live-production work on stage and in broadcast. If you use PPTBridge SK in a show, I would love to hear about it — open an issue or discussion and say hi.

If the plugin saves your next event, a star on the repo is the best way to help more people find it.
