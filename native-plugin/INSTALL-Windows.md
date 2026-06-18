# PPTBridge SK for OBS - Windows Install

Use the Windows ZIP release when you want to install the plugin on another Windows computer.

## Download

Download only:

`pptbridge-obs-windows-x64-v0.5.0-beta.1.zip`

Optional checksum:

`pptbridge-obs-windows-x64-v0.5.0-beta.1.zip.sha256`

## Install

1. Close OBS Studio.
2. Right-click the ZIP and choose `Extract All`.
3. Open the extracted folder.
4. Double-click `INSTALL.cmd`.
5. Allow administrator permission if Windows asks.
6. Start OBS Studio.
7. Add `PPTBridge SK Slide` or `PPTBridge SK Presenter`.
8. Select your PowerPoint file.

If OBS is portable or installed in a custom folder:

```bat
INSTALL.cmd "D:\Path\To\obs-studio"
```

## Live Production Setup

- Use `START / RESTART - Open PowerPoint Live Mode` when you are ready for the live deck.
- Use `STOP - Stop PowerPoint Live Mode` at the end of the deck.
- Keep `Lock OBS Output Size` selected unless you intentionally want OBS to follow the PowerPoint window shape.
- Enable `Tools -> PPTBridge SK: Spotlight/Clicker Capture On/Off` when the presenter clicker must control the Program scene while the operator uses another app.
- Default clicker capture uses `PageDown` and `PageUp`; normal left/right arrows stay free.
- Plain typing keys such as letters, numbers, `Space`, `Enter`, `Tab`, and `Backspace` are never captured globally, so the operator can keep using the computer.
- Put each deck in its own OBS scene for multi-deck shows.

## Current Windows Scope

Windows live production support is focused on PowerPoint decks:

- live PowerPoint slideshow capture
- presenter/source split
- notes and next-slide presenter layout
- Program-scene clicker, hotkey, and OSC routing
- fallback slide rendering and embedded media/audio extraction

Modern `.pptx` decks give the best fallback media metadata. Legacy `.ppt` decks can still open through PowerPoint live/export mode, but embedded-media extraction is best-effort.

PDF decks are still a macOS-only feature in this beta line.

## Build A Release ZIP From Source

After building the Windows DLL:

```powershell
cmake --build native-plugin/build-win --config RelWithDebInfo
powershell -ExecutionPolicy Bypass -File native-plugin/scripts/make-windows-release.ps1
```

The script creates:

- `native-plugin/release/pptbridge-obs-windows-x64-v0.5.0-beta.1.zip`
- `native-plugin/release/pptbridge-obs-windows-x64-v0.5.0-beta.1.zip.sha256`

The release ZIP intentionally contains only user-facing install files and the OBS plugin files.
