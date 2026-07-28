# PPTBridge SK for OBS v0.5.9 - Windows x64

**Stable Windows 10/11 x64 release**

The v0.5.9 Windows release adds native PDF support to the stable live PowerPoint plugin. Download the Windows ZIP, extract it, close OBS, and double-click `INSTALL.cmd`. The ZIP contains only the installer, a short user guide, the plugin DLL, and two required OBS locale files.

## Downloads

- **[Download Windows x64 v0.5.9](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.9/pptbridge-obs-windows-x64-v0.5.9.zip)**
- [Windows SHA-256 checksum](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.9/pptbridge-obs-windows-x64-v0.5.9.zip.sha256)
- **[Download macOS Apple Silicon v0.5.8](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.5.8/pptbridge-obs-macos-apple-silicon.zip)**

Windows and Apple Silicon use separate stable release tags. Intel Mac remains a
[v0.4.4 beta download](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip).

## Highlights

- clean audience output without desktop, PowerPoint menus, borders, or scrollbars
- native PDF pages without PowerPoint or a separate PDF application
- PDF navigation, Presenter, final-page protection, black screen, clicker, and OSC controls
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

The Windows release was validated in real OBS Studio 32.1.2 on Windows 11 x64. PDF testing covered two real multi-page decks, cold and cached loading, exact page counts, navigation, Presenter, black screen, final-page protection, multiple simultaneous PDFs, PDF/PowerPoint coexistence, clicker-style PageDown/PageUp input, OSC, and corrupt-file rejection. PowerPoint 2010 regression testing covered both source types, notes, five Presenter layouts, animations, embedded video/audio, Program/Preview routing, resize, invalid files, simultaneous live decks, repeated Start/Stop cycles, legacy `.ppt`, real event presentations, and a media-heavy deck. The installer was also tested with administrator permission in standard OBS.

## Requirements

- Windows 10/11 x64
- OBS Studio 30 or newer, 64-bit
- Desktop Microsoft PowerPoint for PowerPoint files; not required for PDFs

PDF pages use the built-in Windows PDF engine. Password-protected PDFs are not supported. The DLL and installer are not code-signed yet, so Windows may ask for confirmation. Rehearse every production deck on the exact show computer before the event.

Windows x64 is stable on `v0.5.9`. macOS Apple Silicon remains stable on `v0.5.8` and uses its separate download.
