# PPTBridge SK FAQ

## Which download should I use?

Use the Windows x64 ZIP for Windows 10/11. Use the Apple Silicon ZIP for M-series Macs. Use the Intel ZIP only for older Macs where `About This Mac` says `Processor: Intel`.

## Is Windows supported?

Yes. Windows 10/11 x64 is a stable v0.5.10 release platform with a small ZIP and a double-click `INSTALL.cmd` installer. PDF decks work without PowerPoint; desktop Microsoft PowerPoint is required only for PowerPoint files.

Start here:

- [native-plugin/WINDOWS-RELEASE.md](native-plugin/WINDOWS-RELEASE.md)
- [native-plugin/WINDOWS-TESTING.md](native-plugin/WINDOWS-TESTING.md)

## Do I need PowerPoint?

For `.pptx` live mode, yes. PPTBridge uses PowerPoint for the live slideshow path so animations, click-builds, and embedded media can behave like a real presentation.

For `.pdf` decks on macOS, PowerPoint is not required.

## What is the difference between Slide and Presenter?

`PPTBridge SK Slide` is the clean audience output. Put it in the scene that goes to the projector, stream, switcher, or recording.

`PPTBridge SK Presenter` is for the person presenting. It shows the current slide, next slide, timer, and notes. It is kept lightweight for confidence-monitor stability; live builds, animations, and embedded video should stay in `PPTBridge SK Slide`.

## Is the presenter view PowerPoint Presenter View?

No. PPTBridge renders its own presenter view inside OBS. That makes it easier to resize, crop, place on a confidence monitor, and customize for live production.

## Why does PowerPoint not start automatically?

Manual startup is the default so OBS can open quietly. Open `PPTBridge SK Slide` properties and click `START - Open PowerPoint / Start Live Mode`.

If you want the old automatic behavior, turn on `Auto Start PowerPoint When OBS Opens`.

## Can OBS close the PowerPoint slideshow when OBS quits?

Yes. Turn on `Close PowerPoint Slideshow When OBS Closes` in `PPTBridge SK Slide` properties.

## Why does resizing PowerPoint not change OBS output?

That is intentional when `PowerPoint Resize Behavior` is set to `Lock OBS Output Size`. This lets you shrink the PowerPoint window on your desktop without shrinking the OBS program source.

Use `Follow PowerPoint Window Size` only when you intentionally want the OBS output to follow the PowerPoint window shape.

## How do I control slides?

You can use:

- OBS hotkeys
- source property buttons
- Spotlight/Clicker Capture
- Bitfocus Companion through OBS WebSocket
- local OSC messages

Default hotkeys are `2` for next and `1` for previous.

## Why do normal hotkeys not work while another app is focused?

PPTBridge ignores normal OBS hotkey callbacks while OBS is not active. This prevents accidental slide changes while typing in another app.

If a stage clicker must work globally, enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`.

## How should I use a Logitech Spotlight or similar presenter clicker?

1. Bind PPTBridge next/previous to the keys the clicker sends.
2. Enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`.
3. Grant macOS `Accessibility` and `Input Monitoring` permissions if requested.

Use clicker-style keys such as PageDown/PageUp when possible. Avoid normal typing keys for global capture.

## How do I use Companion or Stream Deck?

Recommended production paths:

- OBS WebSocket `PressInputPropertiesButton`
- PPTBridge local OSC listener

Do not rely on keyboard simulation for Companion if the operator needs to work in other apps.

Full guide: [native-plugin/COMPANION-CONTROL.md](native-plugin/COMPANION-CONTROL.md)

## What OSC paths are supported?

Enable `Tools > PPTBridge SK: Toggle Local OSC Control`, then send UDP OSC to `127.0.0.1:57130`.

Supported paths:

- `/pptbridge/next`
- `/pptbridge/previous`
- `/pptbridge/prev`
- `/pptbridge/first`
- `/pptbridge/last`
- `/pptbridge/black`
- `/pptbridge/blank`
- `/pptbridge/reload`

## Can I use multiple PowerPoint decks?

Yes. Create one OBS scene per deck and put each deck's PPTBridge sources in its own scene. Hotkeys, OSC, and clicker capture follow the current OBS Program scene.

## Can I use PDF files?

Yes, on Windows and macOS. PDF decks render directly without PowerPoint, but PDF pages do not contain PowerPoint animations, click-builds, presenter notes, or embedded PowerPoint media playback.

## Does PPTBridge capture PowerPoint audio?

Embedded presentation audio is verified on the Apple Silicon build. It is routed through the `PPTBridge SK Slide` source, so the source meter, mute control, gain setting, recording, and stream use the same OBS audio path. Only the Slide source produces presentation audio; Presenter is a confidence view.

PPTBridge also includes an optional live PowerPoint app-audio capture path. That path depends on macOS Screen & System Audio Recording permission, OBS, PowerPoint, and the deck, so test it with the exact show computer and presentation before production. If the source status says it is still searching for PowerPoint app audio, verify the permission and restart OBS.

For strict audio routing setups, see [native-plugin/PRO-AUDIO-MODE.md](native-plugin/PRO-AUDIO-MODE.md).

## Why did PPTBridge reject my file?

PPTBridge accepts readable `.pptx` and `.pdf` presentation files. A missing file, unsupported extension, corrupt PDF, or incomplete/corrupt PPTX is rejected before loading and the source status explains the problem. Re-export or download the original deck again instead of renaming another file type to `.pptx` or `.pdf`.

## What should I send with a bug report?

Include:

- OS version
- Mac type or Windows machine
- OBS version
- PPTBridge release
- PowerPoint version
- whether the deck is `.pptx` or `.pdf`
- what you clicked or pressed
- OBS log from `Help > Log Files > View Current Log`

Use [SUPPORT.md](SUPPORT.md) for the full checklist.
