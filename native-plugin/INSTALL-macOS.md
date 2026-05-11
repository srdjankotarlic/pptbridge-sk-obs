# Install PPTBridge SK on macOS

PPTBridge SK ships as separate macOS downloads for Apple Silicon and Intel Macs.

## Fast Install

1. Download the right ZIP for your Mac:

   Apple Silicon:

   <https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip>

   Intel:

   <https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-intel.zip>

2. Unzip it.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If OBS is open, let the installer quit it and continue.
5. The installer will copy the plugin and open OBS.
6. If OBS asks about Safe Mode, choose normal launch so third-party plugins load.
7. Add one of these sources:

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

- Next Slide: `2`
- Previous Slide: `1`

PPTBridge only moves slides from hotkeys while OBS is the active app.
You can bind different keys in OBS Settings > Hotkeys if needed.

## PowerPoint Startup / Shutdown

In `PPTBridge SK Slide` source properties:

- Keep `Auto Start PowerPoint When OBS Opens` off if OBS should open quietly.
- Click `Open PowerPoint / Start Live Mode` when you are ready to launch the slideshow. If PowerPoint is not open yet, PPTBridge opens it for you.
- Turn `Auto Start PowerPoint When OBS Opens` on if you prefer the slideshow to launch as soon as OBS loads the source.
- Keep `Close PowerPoint Slideshow When OBS Closes` on if the slideshow should close when OBS quits.

## Companion / OSC Control

For Stream Deck or Bitfocus Companion control without keyboard focus:

1. In OBS, open `Tools > PPTBridge SK: Toggle Local OSC Control`.
2. In Companion, add a `Generic OSC` connection:
   - Host: `127.0.0.1`
   - Port: `57130`
   - Protocol: `UDP`
3. Add Companion buttons that send OSC paths such as:
   - `/pptbridge/next`
   - `/pptbridge/previous`
   - `/pptbridge/first`
   - `/pptbridge/last`
   - `/pptbridge/black`
   - `/pptbridge/reload`

The release ZIP also includes `COMPANION-CONTROL.md` and `send-osc.sh` for setup/testing.

## Requirements

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
