# Install PPTBridge SK on macOS

PPTBridge SK ships as separate macOS downloads for Apple Silicon and Intel Macs. Apple Silicon is the stable current package; Intel Mac is a beta package from the previous release until new changes are validated on real Intel hardware.

## Which ZIP Should I Download?

| Your Mac | Download |
| --- | --- |
| M1, M2, M3, or M4 Mac | `pptbridge-obs-macos-apple-silicon.zip` |
| Older Intel Mac | `pptbridge-obs-macos-intel.zip` |

To check, open `Apple menu > About This Mac`. If it says `Chip: Apple M...`, use Apple Silicon. If it says `Processor: Intel`, use Intel.

## Fast Install

1. Download the right ZIP for your Mac:

   Apple Silicon:

   <https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest/download/pptbridge-obs-macos-apple-silicon.zip>

   Intel:

   <https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/download/v0.4.4/pptbridge-obs-macos-intel.zip>

2. Unzip it.
3. Double-click `1-Install-PPTBridge-SK.command`.
4. If OBS is open, quit OBS manually and run the installer again.
5. The installer will copy the plugin and open OBS.
6. If OBS asks about Safe Mode, choose normal launch so third-party plugins load.
7. Add one of these sources:

   - `PPTBridge SK Slide`
   - `PPTBridge SK Presenter`

If macOS blocks the command the first time, right-click it and choose `Open`.

## What To Add In OBS

| OBS source | Use it for |
| --- | --- |
| `PPTBridge SK Slide` | Clean audience/program slide output |
| `PPTBridge SK Presenter` | Presenter confidence view with current slide, next slide, timer, notes, and layout customization |

Typical setup:

1. Add `PPTBridge SK Slide` to the scene that goes to the projector, stream, or recording.
2. Add `PPTBridge SK Presenter` to the scene or monitor used by the speaker.
3. Select the same `.pptx` or `.pdf` file in both sources.
4. For `.pptx` live mode, open `PPTBridge SK Slide` properties and click `START / RESTART - Open PowerPoint Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready.
5. For PDF decks, PowerPoint is not required.

If the presenter/operator monitor should show live builds, animations, or
embedded video, keep those in `PPTBridge SK Slide`. `PPTBridge SK Presenter`
stays lightweight and static for notes, next-slide preview, timer, and layout
customization. Live-video presenter preview is postponed until it can be
verified without adding crash risk.

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

- Next Slide: `2` or `Right Arrow`
- Previous Slide: `1` or `Left Arrow`

PPTBridge only moves slides from hotkeys while OBS is the active app.
You can bind different keys in OBS Settings > Hotkeys if needed.
If you want `PageDown`/`PageUp` to work only while OBS is focused, bind them to
`PPTBridge SK: Next Slide` and `PPTBridge SK: Previous Slide`.

For a Logitech Spotlight or another stage clicker while the operator works in
Chrome, OBS, or another app, enable `Tools > PPTBridge SK: Toggle
Spotlight/Clicker Capture`. It captures `PageDown` or `Right` for next and
`PageUp` or `Left` for previous by default, sends those keys to the current OBS
program scene deck, and suppresses them from the focused app. It also captures
custom PPTBridge hotkeys if you bind them in OBS Settings.
This works in PPTX live mode and PDF/cached mode.

If macOS asks, allow OBS in `System Settings > Privacy & Security >
Accessibility` and `Input Monitoring`, then restart OBS or toggle the feature
again. Normal typing keys such as `1` and `2` will be swallowed while this
option is enabled if you bind them as custom clicker keys.

## PowerPoint Startup / Shutdown

In `PPTBridge SK Slide` source properties:

- Keep `Auto Start PowerPoint When OBS Opens` off if OBS should open quietly.
- Click `START / RESTART - Open PowerPoint Live Mode` in the highlighted `PowerPoint Live Start / Stop` group when you are ready to launch the slideshow. If PowerPoint is not open yet, PPTBridge opens it for you.
- If the slideshow window was closed but PowerPoint is still open, click `START / RESTART - Open PowerPoint Live Mode` again to recover the live session.
- Turn `Auto Start PowerPoint When OBS Opens` on if you prefer the slideshow to launch as soon as OBS loads the source.
- Keep `Close PowerPoint Slideshow When OBS Closes` on if the slideshow should close when OBS quits.
- Use `STOP - Stop PowerPoint Live Mode` in the same highlighted group if you want to end the running slideshow without quitting OBS.
- Keep `PowerPoint Resize Behavior` on `Lock OBS Output Size` if you want to shrink the PowerPoint window on your desktop without changing its size in OBS.
- Click `Follow Current PPT Window Size` only when you intentionally want OBS to reflect the current PowerPoint window shape.

Default behavior is manual: OBS opens without immediately popping up the PowerPoint slideshow.

## Multiple PowerPoint Decks

For several decks in one show, create one OBS scene per deck. Add `PPTBridge SK Slide` and, if needed, `PPTBridge SK Presenter` to each scene, then select that scene's `.pptx` in both sources.

Click `START / RESTART - Open PowerPoint Live Mode` on each deck you want ready. PPTBridge locks each live session to its exact staged PowerPoint file, so several slideshow windows can stay open and the current OBS program scene controls the right deck.

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
- Matching Apple Silicon or Intel ZIP for your Mac

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
