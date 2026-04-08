# PPTBridge SK Windows Port Notes

**Author:** Srdjan Kotarlic

This document captures the most practical path for a Windows version of `PPTBridge SK`.

## Honest Status

The current native plugin is **macOS-only** in implementation, even though the product idea is cross-platform.

The biggest blockers are:

- `presentation_document.mm` uses `AppKit`, `Foundation`, and `PDFKit`
- `CMakeLists.txt` links macOS frameworks directly
- rendering for both slide and presenter views is currently done with macOS drawing APIs
- the current PowerPoint fallback uses AppleScript and macOS app bundle discovery

## What Can Be Reused

These parts of the current plugin are still valuable for Windows:

- OBS source registration and source lifecycle
- dual-source workflow: `Slide` and `Presenter`
- hotkey model and shared active-document behavior
- plugin branding, installer/release structure, docs, and publishing flow
- general document state machine: loading, loaded, current slide, black screen, timer

## Best Windows Strategy

The most realistic Windows path is:

1. Keep the existing macOS implementation for macOS builds.
2. Add a Windows-specific `PresentationDocument` backend.
3. On Windows, export slides from PowerPoint to images instead of relying on PDFKit.
4. Read presenter notes either:
   - from PowerPoint COM via `Slide.NotesPage`, or
   - from the `.pptx` package directly.
5. Render the presenter layout with Windows graphics APIs into BGRA pixels for OBS.

## Recommended Export Path On Windows

The cleanest starting point is Microsoft PowerPoint automation on Windows.

Relevant Microsoft docs:

- `Presentation.Export` can export slides to an image format:
  https://learn.microsoft.com/office/vba/api/PowerPoint.Presentation.Export
- `Slide.Export` can export individual slides:
  https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.export
- `Slide.NotesPage` exposes notes pages:
  https://learn.microsoft.com/en-us/office/vba/api/powerpoint.slide.notespage

This suggests the following Windows backend:

- open the `.pptx` with PowerPoint COM
- export each slide as PNG into a cache directory
- extract notes text per slide
- save a compact metadata file for the plugin to load

That avoids bringing a PDF rendering dependency to Windows.

## Recommended Rendering Path On Windows

The macOS presenter renderer uses AppKit text and PDF drawing.

On Windows, the practical equivalent is:

- WIC or GDI+ for image loading and composition
- DirectWrite or GDI text rendering for notes, labels, and timer
- final output written into a BGRA buffer, same as today

## Build-System Changes Needed

Current `CMakeLists.txt` is macOS-specific.

Minimum Windows work:

- switch project languages based on platform
- compile `.mm` only on macOS
- add `.cpp` Windows implementation files
- stop linking AppKit/Foundation/PDFKit/CoreGraphics on Windows
- create Windows packaging outputs in addition to macOS `.plugin` bundle packaging

Official OBS starting point:

- OBS plugin template:
  https://github.com/obsproject/obs-plugintemplate

## Recommended Milestones

### Milestone 1: Architecture split

- separate common logic from macOS drawing/export logic
- introduce platform-specific implementation files
- keep macOS behavior unchanged

### Milestone 2: Windows slide export

- PowerPoint COM export to PNG
- cache directory and slide indexing
- file watching / reload behavior

### Milestone 3: Windows presenter notes

- notes extraction from COM or `.pptx`
- metadata persistence
- parity with current presenter notes behavior

### Milestone 4: Windows presenter renderer

- render current slide image
- render next-slide preview
- render notes text
- render timer and black-screen badge

### Milestone 5: Packaging

- produce Windows zip release
- optionally add an installer later
- document PowerPoint dependency clearly

## Publish Recommendation

Do **not** wait for the Windows port before talking about the project publicly.

Best public positioning right now:

- `PPTBridge SK for OBS v0.1.0`
- `macOS release available now`
- `Windows version planned`

That is honest, still strong for portfolio, and buys time for a proper Windows port instead of a rushed one.

## Next Practical Step

If we continue the Windows work, the best next engineering task is:

**split `presentation_document.mm` into common state logic plus platform backends**

That will reduce risk before implementing PowerPoint COM automation on Windows.
