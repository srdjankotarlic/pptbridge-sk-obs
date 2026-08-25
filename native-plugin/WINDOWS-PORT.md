# PPTBridge SK Windows Port Notes

**Author:** Srdjan Kotarlic

This document captures the current engineering status and next practical path for the Windows version of `PPTBridge SK`.

## Honest Status

Windows x64 `v0.5.10` and macOS Apple Silicon `v0.5.11` are stable release platforms. This document keeps the Windows engineering architecture and remaining limits explicit.

What is already in the Windows code now:

- platform-specific CMake split for macOS vs Windows builds
- Windows `plugin-main.cpp` and `source_presenter.cpp`
- Windows `PresentationDocument` backend in `src/presentation_document_win.cpp`
- native Windows PDF renderer in `src/windows_pdf_renderer.cpp` using `Windows.Data.Pdf`
- PowerPoint-driven slide export on Windows through PowerShell + COM automation
- presenter notes extraction through PowerPoint notes pages
- embedded media extraction from the `.pptx` package for fallback OBS-side playback
- Windows presenter renderer using GDI+
- live slideshow control on Windows for next/previous/first/last
- Windows `Slide` source path in `src/source_slide_win.cpp`
- live slideshow window attachment attempt through OBS `window_capture`
- live PowerPoint process-audio attachment attempt through OBS process audio capture
- fallback to exported slide rendering plus extracted embedded media when the live capture path is not ready
- legacy click-to-play media behavior so a media-heavy slide can stay on screen and start playback before advancing
- manual PowerPoint startup with highlighted `START / RESTART - Open PowerPoint Live Mode`
- highlighted `STOP - Stop PowerPoint Live Mode`
- optional `Auto Start PowerPoint When OBS Opens`
- optional slideshow cleanup when OBS closes
- locked OBS output sizing when the PowerPoint slideshow window is resized
- optional follow-window resize behavior
- current Program scene routing for hotkeys, local OSC, and clicker capture
- multi-deck routing by source `pptx_path`
- optional Windows Spotlight/Clicker Capture using the same OBS hotkey bindings
- local OSC / Companion control through the shared OSC server path

What is **not** included yet:

- password-protected PDF support
- a code-signed Windows installer

The Windows `v0.5.10` release has real OBS runtime coverage for native PDF and PowerPoint workflows, including Presenter, nested multi-deck routing, same-name file isolation, clicker/OSC, white-frame recovery, live video/audio, legacy `.ppt`, repeated lifecycle/resource stress, bounded cache behavior, concurrent PDF rendering, and the rollback-safe five-file installer ZIP. It also includes a verified `Program Files` administrator-permission installation path.

## What Was Reused

These parts of the current plugin are still valuable for Windows:

- OBS source registration and source lifecycle
- dual-source workflow: `Slide` and `Presenter`
- hotkey model and shared active-document behavior
- plugin branding, installer/release structure, docs, and publishing flow
- general document state machine: loading, loaded, current slide, black screen, timer

## Current Windows Strategy

The most realistic Windows path is:

1. Keep the existing macOS implementation untouched for shipping mac builds.
2. Add a Windows-specific `PresentationDocument` backend.
3. Use PowerPoint on Windows as the control/export engine through PowerShell + COM.
4. Export slides to cached PNGs for the safe fallback render path.
5. Extract embedded media from the `.pptx` package so OBS can still render or mix that media when live slideshow capture is unavailable.
6. Keep the live-show path focused on real PowerPoint slideshow control and OBS-side attachment to the slideshow window/audio process.
7. Keep manual startup as the default so OBS can open quietly unless the user enables auto-start.
8. Route controls through the current OBS Program scene so multi-deck shows can work cleanly.
9. Render presenter layout in-plugin with Windows graphics APIs.

## Recommended Export Path On Windows

The cleanest starting point is Microsoft PowerPoint automation on Windows.

Relevant Microsoft docs:

- `Presentation.Export` can export slides to an image format:
  https://learn.microsoft.com/office/vba/api/PowerPoint.Presentation.Export
- `Slide.Export` can export individual slides:
  https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.export
- `Slide.NotesPage` exposes notes pages:
  https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.notespage

That led to the following Windows backend shape:

- open the `.pptx` with PowerPoint COM
- export each slide as PNG into a cache directory
- extract notes text per slide
- inspect the PPTX package for embedded media placement and media files
- save compact slide metadata for the plugin to reload quickly

PDF files use the built-in Windows `Windows.Data.Pdf` API and are cached as PNG pages, so no third-party PDF runtime or separate PDF application is shipped.

## Recommended Rendering Path On Windows

The macOS presenter renderer uses AppKit text and PDF drawing.

On Windows, the practical equivalent is:

- WIC or GDI+ for image loading and composition
- DirectWrite or GDI text rendering for notes, labels, and timer
- final output written into a BGRA buffer, same as today

## Build-System Status

These pieces are now in place:

- project languages switch by platform
- `.mm` sources stay on macOS
- `.cpp` Windows sources are added for Windows builds
- macOS frameworks are not linked on Windows
- Windows build output is prepared as a DLL-style OBS plugin build path

Windows packaging now includes a five-file release ZIP, automatic install-location detection, administrator elevation for normal OBS installations, SHA256 generation, and public-package wording checks. Code signing remains future work.

Official OBS starting point:

- OBS plugin template:
  https://github.com/obsproject/obs-plugintemplate

## Remaining Milestones

### Milestone 1: Real Windows runtime validation

- confirm the new Windows sources compile on a real Windows machine
- confirm the plugin DLL loads into OBS
- confirm `window_capture` attaches to the real PowerPoint slideshow window
- confirm `wasapi_process_output_capture` works with the expected OBS build
- confirm manual START/STOP works
- confirm locked resize keeps the OBS source stable when the PowerPoint window is resized
- confirm hotkeys, clicker capture, and OSC route to the current Program scene
- confirm two or more open decks can coexist across separate OBS scenes

### Milestone 2: Live parity hardening

- verify click-builds and animations in real OBS
- verify embedded video behavior
- verify audio ownership and OBS mixer control
- verify the new fallback media extraction path against real PowerPoint decks
- add Windows-specific recovery logic where needed

### Milestone 3: Packaging

- produce Windows release zip
- add Windows install docs
- optionally add an installer later

## Next Practical Step

Continue expanding the real-hardware matrix across Windows 10/11, current Microsoft 365 PowerPoint, additional OBS 30+ releases, and physical presenter remotes while keeping the full Windows release checklist green.
