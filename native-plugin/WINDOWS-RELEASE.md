# PPTBridge SK Windows x64 Stable Release

**Release:** `v0.5.8`

This stable release brings the Windows PowerPoint workflow alongside the macOS v0.5.8 release while keeping installation to one small ZIP and a double-click `INSTALL.cmd`.

## Download

Download `pptbridge-obs-windows-x64-v0.5.8.zip`, extract it, close OBS, and double-click `INSTALL.cmd`.

The ZIP contains only:

- `INSTALL.cmd`
- `README.txt`
- `obs-plugins/64bit/pptbridge-obs.dll`
- `data/obs-plugins/pptbridge-obs/locale/en-US.ini`
- `data/obs-plugins/pptbridge-obs/locale/en-GB.ini`

## What Works

- clean PowerPoint audience output without desktop, PowerPoint chrome, scrollbars, or Presenter View artifacts
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
- clear, safe errors for missing, empty, corrupt, unsupported, and PDF inputs

## Validation

The release candidate was built in both `RelWithDebInfo` and clean `Release` configurations, then tested in real OBS Studio 32.1.2 on Windows 11 x64 with desktop PowerPoint 2010. Validation covered fresh and cached loads, animations, notes, video/audio, final-slide navigation, resize, Presenter layouts, cue export, all six OSC controls, all 16 OSC feedback addresses, Program/Preview clicker isolation, three simultaneous live decks, ten rapid Start/Stop cycles, legacy `.ppt`, six real event decks, and an 8.6 GB media-heavy deck.

The installer was additionally tested through a real Windows administrator-permission elevation into the standard OBS `Program Files` directory, including reinstall and post-install DLL/locale verification.

The final public ZIP must pass the same runtime suite after a fresh extraction and installation before the GitHub asset is published.

## Important Audio Note

PowerPoint runs all open decks in one application process. PPTBridge routes process audio only from the current Program scene. If several PPTBridge Slide sources are intentionally visible in that same Program scene, keep **Route PowerPoint App Audio Through OBS** enabled on only one of them to avoid duplicate mixing.

## Known Limits

- Rehearse every event deck on the exact production computer before a paid or critical show.
- PDF input is not enabled on Windows.
- The plugin and installer are not code-signed yet, so Windows may show a security confirmation.
- Desktop Microsoft PowerPoint is required; PowerPoint for the web is not supported.

The Windows x64 and macOS Apple Silicon ZIPs are published together in the stable `v0.5.8` GitHub release.
