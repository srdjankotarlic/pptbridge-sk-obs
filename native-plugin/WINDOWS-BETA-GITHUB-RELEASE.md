# PPTBridge SK for OBS v0.5.8-windows-beta.1

**Windows 10/11 x64 prerelease**

This is the easy-install Windows PowerPoint beta. Download the ZIP, extract it, close OBS, and double-click `INSTALL.cmd`. The download contains only the installer, a short user guide, the plugin DLL, and two required OBS locale files.

## Downloads

- `pptbridge-obs-windows-x64-v0.5.8-windows-beta.1.zip`
- `pptbridge-obs-windows-x64-v0.5.8-windows-beta.1.zip.sha256`

## Highlights

- clean audience output without desktop, PowerPoint menus, borders, or scrollbars
- live animations, click builds, embedded video, and PowerPoint audio in OBS
- Presenter source with notes, next slide, timer, cue list, layouts, and backgrounds
- PowerPoint window resize does not change the configured OBS output size
- extra Next presses on the final slide keep the slideshow open
- several live PowerPoint decks can stay ready at the same time
- Logitech Spotlight/PageDown/PageUp follows only the current OBS Program scene while the operator keeps using other apps
- Studio Preview does not steal clicker control or PowerPoint audio
- legacy `.ppt` and modern PowerPoint formats
- automatic recovery and manual Reattach after a slideshow/window interruption
- fast live startup for very large media decks without copying embedded video into the cache

## Tested

The release candidate was validated in real OBS Studio 32.1.2 on Windows 11 x64 with desktop PowerPoint 2010. Testing covered both source types, uncached/cached loading, notes, five Presenter layouts, animations, embedded video/audio, Program/Preview routing, global clicker capture, all OSC controls and feedback addresses, resize, final-slide protection, invalid files, three simultaneous live decks, ten rapid Start/Stop cycles, legacy `.ppt`, six real event presentations, and an 8.6 GB media-heavy deck.

## Requirements

- Windows 10/11 x64
- OBS Studio 30 or newer, 64-bit
- Desktop Microsoft PowerPoint

PDF input is not enabled in this Windows beta. The DLL and installer are not code-signed yet, so Windows may ask for confirmation. Rehearse every production deck on the exact show computer before the event.

The separate macOS `v0.5.8` release remains the stable macOS download. This Windows release is intentionally marked **Prerelease** and does not replace it.
