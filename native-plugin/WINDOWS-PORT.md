# PPTBridge SK Windows Port Notes

**Author:** Srdjan Kotarlic

This document captures the current engineering status and next practical path for the Windows version of `PPTBridge SK`.

## Honest Status

The public release is still **macOS-first**, but the repo now contains the first serious Windows implementation layer.

What is already in the Windows code now:

- platform-specific CMake split for macOS vs Windows builds
- Windows `plugin-main.cpp` and `source_presenter.cpp`
- Windows `PresentationDocument` backend in `src/presentation_document_win.cpp`
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

What is **not** claimed as done yet:

- verified Windows runtime parity with the macOS release
- proven embedded video/audio parity in a real Windows OBS test
- Windows packaging and installer flow
- a public Windows release zip

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
7. Render presenter layout in-plugin with Windows graphics APIs.

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

That avoids bringing a PDF rendering dependency to Windows while still giving the fallback path more than just flat images.

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

Still left for Windows packaging:

- final install layout validation against a real Windows OBS install
- release zip script
- optional installer

Official OBS starting point:

- OBS plugin template:
  https://github.com/obsproject/obs-plugintemplate

## Remaining Milestones

### Milestone 1: Real Windows runtime validation

- confirm the new Windows sources compile on a real Windows machine
- confirm `window_capture` attaches to the real PowerPoint slideshow window
- confirm `wasapi_process_output_capture` works with the expected OBS build

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

The next best engineering task is no longer architecture split. That part is started.

The next best task is:

**move this Windows backend onto a real Windows OBS machine and validate live capture, live audio, and PowerPoint parity against real decks**

That is the point where the Windows code becomes either a releasable alpha or gets another hardening pass.
