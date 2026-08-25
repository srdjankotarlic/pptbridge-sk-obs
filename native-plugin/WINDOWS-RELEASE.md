# PPTBridge SK Windows x64 Stable Release

**Release:** `v0.5.10`

This stable Windows release hardens the existing live PowerPoint and native PDF workflows for repeated live-production use while keeping installation to one small ZIP and a double-click `INSTALL.cmd`.

## Download

Download `pptbridge-obs-windows-x64-v0.5.10.zip`, extract it, close OBS, and double-click `INSTALL.cmd`.

The ZIP contains only:

- `INSTALL.cmd`
- `README.txt`
- `obs-plugins/64bit/pptbridge-obs.dll`
- `data/obs-plugins/pptbridge-obs/locale/en-US.ini`
- `data/obs-plugins/pptbridge-obs/locale/en-GB.ini`

## What Works

- clean PowerPoint audience output without desktop, PowerPoint chrome, scrollbars, or Presenter View artifacts
- native PDF rendering through Windows with no PowerPoint or separate PDF program required
- `PPTBridge SK Slide` and `PPTBridge SK Presenter` sources
- live animations, click builds, embedded video, and PowerPoint process audio
- presenter notes, next-slide preview, timer, cue list, five layouts, preview scaling, and custom backgrounds
- fixed OBS output size while the PowerPoint window is moved or resized
- final-slide protection so extra Next presses do not close the slideshow
- manual Start, Stop, Restart, Reattach, optional Auto Start, and automatic recovery
- multiple simultaneous PowerPoint live sessions using full canonical file paths
- Program-scene routing for OBS hotkeys, local OSC, and Logitech Spotlight/PageDown/PageUp clickers
- Studio Preview isolation so Preview does not steal clicker control or PowerPoint audio
- legacy binary `.ppt` files as well as modern PowerPoint formats
- fast live startup for very large media decks without copying embedded video into the slide cache
- exact live-window isolation for different decks that have the same filename
- clicker, OSC, and audio routing through nested OBS scenes
- last-good-frame protection while OBS Window Capture hooks or reattaches
- bounded, transactional caches with active-session protection and junction-safe cleanup
- serialized cross-process PDF rendering for GPU-driver stability
- transactional install/reinstall with automatic rollback if activation fails
- clear, safe errors for missing, empty, corrupt, unsupported, and password-protected inputs

## Validation

The release candidate was built cleanly in `Release`, then tested in real OBS Studio 32.1.2 on Windows 11 x64. Native PDF validation covered fresh/cached loads, three real multi-page documents, exact page counts, navigation, Presenter, black screen, final-page protection, simultaneous PDFs, PDF/PowerPoint coexistence, clicker, OSC, corrupt/password-protected rejection, reload recovery, and parallel rendering from separate processes. Desktop PowerPoint 2010 validation covered animation pixels, notes, video/audio, final-slide navigation, resize, Presenter layouts, cue export, nested Program/Preview routing, same-name files, simultaneous live decks, ten repeated Start/Stop cycles, legacy `.ppt`, real event decks, and an 8 GB media-heavy deck. Three repeated core suites confirmed a stable OBS memory/handle/thread plateau after cleanup.

The installer was additionally tested from a fresh five-file ZIP in paths containing spaces and non-ASCII characters, through a real Windows administrator-permission elevation into the standard OBS `Program Files` directory, and through reinstall, stale-file cleanup, locked-DLL rollback, invalid target, missing payload, and post-install DLL/locale verification.

The final public ZIP must pass the same runtime suite after a fresh extraction and installation before the GitHub asset is published.

## Important Audio Note

PowerPoint runs all open decks in one application process. PPTBridge routes process audio only from the current Program scene. If several PPTBridge Slide sources are intentionally visible in that same Program scene, keep **Route PowerPoint App Audio Through OBS** enabled on only one of them to avoid duplicate mixing.

## Known Limits

- Rehearse every event deck on the exact production computer before a paid or critical show.
- Password-protected PDFs are not supported.
- The plugin and installer are not code-signed yet, so Windows may show a security confirmation.
- Desktop Microsoft PowerPoint is required only for PowerPoint files; PowerPoint for the web is not supported.

Windows x64 is published as stable `v0.5.10`; macOS Apple Silicon is stable on `v0.5.11`.
