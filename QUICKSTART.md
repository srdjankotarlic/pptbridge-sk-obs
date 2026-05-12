# PPTBridge SK Quickstart

This is the shortest path from download to a working OBS presentation scene.

## 1. Download The Right ZIP

| Your Mac | Download |
| --- | --- |
| M1, M2, M3, or M4 | [`pptbridge-obs-macos-apple-silicon.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip) |
| Intel Mac | [`pptbridge-obs-macos-intel.zip`](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-intel.zip) |

To check your Mac type, open `Apple menu > About This Mac`.

## 2. Install

1. Unzip the download.
2. Open `START-HERE-macOS.txt`.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If macOS blocks it, right-click the command and choose `Open`.
5. Let the installer copy the plugin and open OBS.
6. If OBS asks about Safe Mode, choose normal launch so third-party plugins load.

## 3. Add The OBS Sources

In OBS, open the `Sources` panel and click `+`.

Add:

- `PPTBridge SK Slide`
- `PPTBridge SK Presenter`

Use `PPTBridge SK Slide` for the audience feed. Use `PPTBridge SK Presenter` for the speaker monitor or operator preview.

## 4. Select Your Deck

Open each PPTBridge source's properties and select the same presentation file:

- `.pptx` for PowerPoint decks
- `.pdf` for PDF decks on macOS

For `.pptx` live mode, Microsoft PowerPoint must be installed.

## 5. Start PowerPoint Live Mode

For PowerPoint decks:

1. Open `PPTBridge SK Slide` properties.
2. Find the highlighted `PowerPoint Live Start / Stop` section.
3. Click `START - Open PowerPoint / Start Live Mode`.

By default, OBS opens quietly and does not start PowerPoint until you click `START`.

## 6. Control Slides

Default OBS hotkeys:

- `2` = next slide
- `1` = previous slide

To change them:

1. Open `OBS Settings > Hotkeys`.
2. Search for `PPTBridge SK`.
3. Set `Next Slide` and `Previous Slide`.
4. Click `Apply`.

PPTBridge only accepts normal OBS hotkeys while OBS is the active app, so typing in another app will not move slides.

## 7. Use A Stage Clicker While Another App Is Focused

If a presenter clicker must work while the operator uses Chrome, OBS, or another app:

1. Bind PPTBridge next/previous to the keys the clicker sends.
2. In OBS, open `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`.
3. If macOS asks, allow OBS in:
   - `System Settings > Privacy & Security > Accessibility`
   - `System Settings > Privacy & Security > Input Monitoring`
4. Restart OBS or toggle the feature again.

Use clicker-style keys such as PageDown/PageUp when possible. If you bind normal typing keys such as `1` and `2`, those keys will be swallowed while Spotlight/Clicker Capture is enabled.

## 8. Companion Or Stream Deck

For Bitfocus Companion or Stream Deck, avoid keyboard simulation. Use one of these:

- OBS WebSocket `PressInputPropertiesButton`
- PPTBridge local OSC listener

Local OSC:

- enable `Tools > PPTBridge SK: Toggle Local OSC Control`
- send UDP OSC to `127.0.0.1:57130`
- use paths such as `/pptbridge/next` and `/pptbridge/previous`

Full guide: [native-plugin/COMPANION-CONTROL.md](native-plugin/COMPANION-CONTROL.md)

## 9. Multiple Decks

For several presentations in one show:

1. Create one OBS scene per deck.
2. Add `PPTBridge SK Slide` to each scene.
3. Add `PPTBridge SK Presenter` if the presenter needs notes.
4. Select that scene's `.pptx` in both sources.
5. Start live mode for each deck you want ready.

Hotkeys, OSC, and clicker capture follow the current OBS Program scene.

## 10. If Something Fails

| Problem | First thing to try |
| --- | --- |
| PPTBridge sources do not appear | Restart OBS normally, not Safe Mode |
| macOS blocks the installer | Right-click the command and choose `Open` |
| Slides do not load | Check the file path and click `Reload Presentation` |
| PowerPoint does not start | Confirm Microsoft PowerPoint is installed |
| Clicker does not work globally | Enable Spotlight/Clicker Capture and grant macOS permissions |
| Notes are missing | Check whether the original `.pptx` actually contains presenter notes |

More help:

- [SETUP-GUIDE.md](SETUP-GUIDE.md)
- [FAQ.md](FAQ.md)
- [SUPPORT.md](SUPPORT.md)
