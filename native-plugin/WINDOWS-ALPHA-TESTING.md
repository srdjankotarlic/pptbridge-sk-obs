# PPTBridge SK Windows Beta Testing

This checklist is for the first real Windows runtime validation of the native PPTBridge SK beta backend.

## Goal

Confirm that the Windows build can:

- show `PPTBridge SK Slide` and `PPTBridge SK Presenter` in OBS
- load real PowerPoint decks directly from source properties
- open PowerPoint live mode only when the user clicks `START` unless auto-start is enabled
- stop PowerPoint live mode with `STOP` and optionally on OBS quit
- preserve live PowerPoint animations and click-builds in `True Live PowerPoint Mode`
- keep OBS output locked when the PowerPoint window is resized
- render presenter notes, next-slide preview, timer, and presenter layout presets
- route OBS hotkeys, local OSC, and clicker capture to the current OBS Program scene
- support multiple OBS scenes with different PowerPoint decks
- attach PowerPoint audio into OBS when the OBS build supports the expected Windows capture path
- fall back to exported slides plus extracted embedded media when live attachment is unavailable

## What To Install On The Windows Machine

- OBS Studio 30 or newer, 64-bit
- Microsoft PowerPoint for Windows
- Visual Studio 2022 with the Desktop development with C++ workload
- CMake
- Git
- a local checkout of this repo
- an OBS source tree checkout for headers, matching the OBS version as closely as practical

## Build

From the repo root in PowerShell:

```powershell
cmake -S native-plugin -B native-plugin/build-win `
  -DOBS_SOURCE_DIR=C:\path\to\obs-studio `
  -DOBS_APP_DIR="C:\Program Files\obs-studio"

cmake --build native-plugin/build-win --config RelWithDebInfo
```

If CMake cannot find OBS libraries, point it to the installed OBS app or OBS build folder. Save the exact CMake error for the report.

## Install Into OBS

Copy the built plugin files into the OBS plugin folders for that machine.

Expected Windows install layout:

- `C:\Program Files\obs-studio\obs-plugins\64bit\pptbridge-obs.dll`
- `C:\Program Files\obs-studio\data\obs-plugins\pptbridge-obs\...`

For a user-local test, use a portable OBS folder if you do not want to touch the main OBS install.

## Test Deck Types

Use at least these decks:

1. Small deck with plain slides only
2. Deck with presenter notes
3. Deck with click-build animations
4. Deck with embedded video
5. Deck with embedded audio-only media
6. Two different decks in two different OBS scenes

## OBS Test Checklist

### Source Registration

- confirm `PPTBridge SK Slide` appears in the OBS source picker
- confirm `PPTBridge SK Presenter` appears in the OBS source picker

### Basic Slide Workflow

- add `PPTBridge SK Slide`
- point it to a real `.pptx`
- verify the first slide appears
- verify `Next`, `Previous`, `First`, `Last`, `Toggle Black Screen`, and `Reload Presentation`
- verify OBS hotkeys control the active deck only while OBS is focused
- type in Notepad/Chrome and verify normal typing does not move slides

### PowerPoint Startup And Stop

- leave `Use True Live PowerPoint Mode` enabled
- leave `Auto Start PowerPoint When OBS Opens` disabled
- restart OBS and verify PowerPoint does not pop up immediately
- open source properties and click `START - Open PowerPoint / Start Live Mode`
- verify the slideshow starts and OBS attaches the live path
- click `STOP - Stop PowerPoint Live Mode`
- verify the slideshow stops without quitting OBS
- enable `Auto Start PowerPoint When OBS Opens`, restart OBS, and verify automatic startup works
- enable `Close PowerPoint Slideshow When OBS Closes`, close OBS, and verify the slideshow is cleaned up

### Resize Lock

- with live mode running, set `PowerPoint Resize Behavior` to `Lock OBS Output Size`
- shrink or resize the PowerPoint slideshow window
- verify the OBS scene source stays filled and does not get smaller
- switch to `Follow PowerPoint Window Size`
- resize the slideshow window again and verify OBS follows that shape intentionally

### Presenter Workflow

- add `PPTBridge SK Presenter`
- point it to the same deck
- verify notes render for a deck that actually contains notes
- verify the next-slide preview updates correctly
- verify the timer starts and keeps incrementing
- test layout presets, notes size, notes zoom, notes area, and preview fit/fill/crop

### Multi-Deck Scene Routing

- create Scene A with Deck A `PPTBridge SK Slide` and optional presenter source
- create Scene B with Deck B `PPTBridge SK Slide` and optional presenter source
- start live mode for both decks
- switch OBS Program to Scene A and press next; only Deck A should move
- switch OBS Program to Scene B and press next; only Deck B should move
- repeat with local OSC `/pptbridge/next`

### Spotlight/Clicker Capture

- use the built-in presenter keys or bind PPTBridge next/previous to unusual clicker keys
- enable `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture`
- focus Notepad, Chrome, or another app
- press the clicker
- verify PPTBridge moves the current Program scene deck
- verify the clicker key does not type into the focused app
- disable the feature and verify the key behaves normally again

### Local OSC / Companion

- enable `Tools > PPTBridge SK: Toggle Local OSC Control`
- send `/pptbridge/next` to `127.0.0.1:57130` over UDP
- confirm the current Program scene deck advances
- repeat for `/pptbridge/previous`, `/pptbridge/first`, `/pptbridge/last`, `/pptbridge/black`, and `/pptbridge/reload`

### Audio

- verify `PPTBridge SK Slide` appears as an OBS audio source or creates the expected child audio path
- verify the OBS mixer meter moves on a deck with audio/video
- verify mute and volume in OBS affect the captured show audio
- if the live window capture audio path is unavailable, verify the process-audio fallback path

### Fallback Behavior

- disable `Use True Live PowerPoint Mode`
- verify exported slides still render
- verify media-heavy slides can use the fallback click-to-play behavior
- verify the slide stays on the current page when media is armed before advancing

## Known Current Limits

- This Windows backend has not yet been runtime-proven on a real Windows OBS machine
- PDF input is not enabled yet in this Windows beta
- local audio ownership may vary depending on OBS version and Windows capture support
- no one-click Windows installer is included yet

## What Feedback To Send Back

Please report:

- Windows version
- OBS version
- PowerPoint version
- whether the plugin built successfully
- whether the plugin loaded successfully
- whether the two source types appeared
- whether live slideshow capture attached
- whether resize lock worked
- whether multi-deck routing worked
- whether Spotlight/Clicker Capture worked
- whether local OSC/Companion worked
- whether animations matched PowerPoint
- whether video rendered
- whether audio landed in the OBS mixer
- whether fallback media worked when live mode was disabled
- OBS log file if anything failed
