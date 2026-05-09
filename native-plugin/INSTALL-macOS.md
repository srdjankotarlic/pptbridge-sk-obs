# Install PPTBridge SK on macOS

PPTBridge SK currently ships as an Apple Silicon macOS build.

## Fast Install

1. Download the latest macOS ZIP:

   <https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-arm64.zip>

2. Unzip it.
3. Quit OBS if it is open.
4. Double-click `Install-PPTBridge-SK.command`.
5. The installer will copy the plugin and open OBS.
6. Add one of these sources:

   - `PPTBridge SK Slide`
   - `PPTBridge SK Presenter`

If macOS blocks the command the first time, right-click it and choose `Open`.

## Manual Install

If you prefer to install by hand, copy:

```text
pptbridge-obs.plugin
```

into:

```text
~/Library/Application Support/obs-studio/plugins/
```

Then restart OBS.

## After Install

Open `Settings > Hotkeys` in OBS and search for `PPTBridge SK`.

Default bindings are:

- Next Slide: `2`, `Page Down`, `Right Arrow`, `Space`
- Previous Slide: `1`, `Page Up`, `Left Arrow`
- Toggle Black Screen: `B`
- First Slide: `Home`
- Last Slide: `End`

## Requirements

- Apple Silicon Mac
- macOS 12 or newer
- OBS Studio 30 or newer
- Microsoft PowerPoint for `.pptx` live mode

PDF decks can be used without PowerPoint.

## If It Does Not Show Up in OBS

1. Make sure OBS was fully restarted after installation.
2. Make sure OBS did not start in Safe Mode.
3. Open `Help > Log Files > View Current Log`.
4. Search for:

   ```text
   PPTBridge SK
   ```

If the log does not show `Native plugin loaded`, open a GitHub issue and include the OBS log.
