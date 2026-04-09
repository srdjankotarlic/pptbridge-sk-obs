# PPTBridge SK Windows Alpha Testing

**Author:** Srdjan Kotarlic

This checklist is for the first real Windows runtime validation of the native PPTBridge SK backend.

## Goal

Confirm that the Windows build can:

- show `PPTBridge SK Slide` and `PPTBridge SK Presenter` in OBS
- load a real PowerPoint deck directly from source properties
- keep slide state in sync through OBS hotkeys
- preserve live PowerPoint animations and click-builds in `True Live PowerPoint Mode`
- render presenter notes and next-slide preview
- attach the live slideshow window as the preferred OBS capture path
- attach PowerPoint audio into OBS when the OBS build supports the expected Windows capture path
- fall back to exported slides plus extracted embedded media when live attachment is unavailable

## What To Install On The Windows Machine

- OBS Studio
- Microsoft PowerPoint
- Visual Studio 2022 Build Tools or Visual Studio with C++ workload
- CMake
- a local checkout of the `pptbridge-sk-obs` repo
- an OBS source tree checkout for headers if needed by the local CMake configuration

## Build

From the repo root:

```powershell
cmake -S native-plugin -B native-plugin/build-win `
  -DOBS_SOURCE_DIR=C:\path\to\obs-studio `
  -DOBS_APP_DIR="C:\Program Files\obs-studio"

cmake --build native-plugin/build-win --config RelWithDebInfo
```

## Install Into OBS

Copy the built plugin files into the OBS plugin folders for that machine.

Expected Windows install layout:

- `obs-plugins/64bit/pptbridge-obs.dll`
- `data/obs-plugins/pptbridge-obs/...`

## Test Deck Types

Use at least these decks:

1. Small deck with plain slides only
2. Deck with presenter notes
3. Deck with click-build animations
4. Deck with embedded video
5. Deck with embedded audio-only media
6. Large deck with many slides and at least one media slide

## OBS Test Checklist

### Source Registration

- confirm `PPTBridge SK Slide` appears in the OBS source picker
- confirm `PPTBridge SK Presenter` appears in the OBS source picker

### Basic Slide Workflow

- add `PPTBridge SK Slide`
- point it to a real `.pptx`
- verify the first slide appears
- verify `Next`, `Previous`, `First`, `Last`, and `Black Screen`
- verify OBS hotkeys control the active deck

### Presenter Workflow

- add `PPTBridge SK Presenter`
- point it to the same deck
- verify notes render for a deck that actually contains notes
- verify the next-slide preview updates correctly
- verify the timer starts and keeps incrementing

### Live PowerPoint Mode

- leave `Use True Live PowerPoint Mode` enabled
- confirm PowerPoint opens and starts a slideshow session
- confirm OBS shows the live slideshow path instead of only the fallback cached slide
- verify click-builds and animations behave like real PowerPoint
- verify embedded video starts correctly on the live slideshow

### Audio

- verify `PPTBridge SK Slide` appears as an OBS audio source
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
- PDF input is not enabled yet in this Windows alpha
- local audio ownership may still vary depending on the exact OBS build and Windows capture support available

## What Feedback To Send Back

Please report:

- Windows version
- OBS version
- whether the plugin loaded successfully
- whether the two source types appeared
- whether live slideshow capture attached
- whether animations matched PowerPoint
- whether video rendered
- whether audio landed in the OBS mixer
- whether fallback media worked when live mode was disabled
- the OBS log file if anything failed
