# PPTBridge SK for OBS v0.5.8 - Windows x64

**Stable Windows 10/11 x64 release**

The v0.5.8 release now includes the stable easy-install Windows PowerPoint plugin alongside Apple Silicon. Download the Windows ZIP, extract it, close OBS, and double-click `INSTALL.cmd`. The ZIP contains only the installer, a short user guide, the plugin DLL, and two required OBS locale files.

## Downloads

- `pptbridge-obs-windows-x64-v0.5.8.zip`
- `pptbridge-obs-windows-x64-v0.5.8.zip.sha256`

## Highlights

- clean audience output without desktop, PowerPoint menus, borders, or scrollbars
- live animations, click builds, embedded video, and PowerPoint audio in OBS
- Presenter source with notes, next slide, timer, cue list, layouts, and backgrounds
- PowerPoint window resize does not change the configured OBS output size
- extra Next presses on the final slide keep the slideshow open
- several live PowerPoint decks can stay ready at the same time
- Logitech Spotlight and other remotes that send PageDown/PageUp follow only the current OBS Program scene while the operator keeps using other apps
- Studio Preview does not steal clicker control or PowerPoint audio
- legacy `.ppt` and modern PowerPoint formats
- automatic recovery and manual Reattach after a slideshow/window interruption
- fast live startup for very large media decks without copying embedded video into the cache
- reliable administrator-permission installation into a normal OBS `Program Files` folder

## Tested

The Windows release was validated in real OBS Studio 32.1.2 on Windows 11 x64 with desktop PowerPoint 2010. Testing covered both source types, uncached/cached loading, notes, five Presenter layouts, animations, embedded video/audio, Program/Preview routing, simulated PageDown/PageUp clicker input, all OSC controls and feedback addresses, resize, final-slide protection, invalid files, three simultaneous live decks, ten rapid Start/Stop cycles, legacy `.ppt`, six real event presentations, an 8.6 GB media-heavy deck, and a real administrator-permission install into standard OBS.

## Requirements

- Windows 10/11 x64
- OBS Studio 30 or newer, 64-bit
- Desktop Microsoft PowerPoint

PDF input is not enabled on Windows. The DLL and installer are not code-signed yet, so Windows may ask for confirmation. Rehearse every production deck on the exact show computer before the event.

Windows x64 and macOS Apple Silicon are both stable platforms in the same `v0.5.8` release.
