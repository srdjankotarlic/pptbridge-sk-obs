# PPTBridge SK Windows Beta Preview

**Current beta:** `v0.5.0-beta.1` source validation pack

This is a Windows beta preview of `PPTBridge SK`. It is prepared so the Windows version can be built and tested on a real Windows OBS machine. It is not a final one-click installer yet.

## What This Windows Beta Is Meant To Do

- register `PPTBridge SK Slide` and `PPTBridge SK Presenter` as native OBS source types
- load a PowerPoint file directly from OBS source properties
- prefer true live PowerPoint slideshow behavior for animations, click-builds, and embedded media
- keep OBS output locked to the OBS canvas when the PowerPoint slideshow window is resized
- optionally follow the current PowerPoint window size when that is intentional
- provide clear `START - Open PowerPoint / Start Live Mode` and `STOP - Stop PowerPoint Live Mode` buttons
- let the user choose manual startup or `Auto Start PowerPoint When OBS Opens`
- optionally stop the slideshow when OBS closes
- route hotkeys, local OSC, and clicker capture to the PPTBridge source in the current OBS Program scene
- support multi-deck shows where each OBS scene has a different PowerPoint deck
- render a dedicated presenter view with notes, next-slide preview, timer, and presenter layout customization
- attempt to bring PowerPoint audio into OBS through the live window path or Windows process-audio fallback
- fall back to exported slide rendering plus extracted embedded media if the live path is not ready

## What The Beta Pack Includes

- current Windows-oriented native plugin source tree
- Windows build and test instructions
- Windows Codex handoff prompt for the validation laptop
- current docs and release notes

## Honest Current Limits

- this Windows beta still needs runtime proof on a real Windows OBS machine
- it is not yet a one-click Windows installer
- PDF input is not enabled in this Windows beta path
- exact audio ownership can vary by OBS build and Windows capture support available on that machine
- the macOS `v0.4.3` ZIPs remain the stable public release for normal users

## Best Current Usage Goal

Use this beta on a Windows test machine to answer these questions:

- does the source compile and load into OBS
- do the two source types appear in OBS
- does manual `START` open PowerPoint and attach the live slideshow
- does `STOP` end the slideshow
- does resizing the PowerPoint window leave OBS output unchanged when `Lock OBS Output Size` is selected
- do multiple OBS scenes control separate PowerPoint decks
- do OBS-focused hotkeys ignore typing in other apps
- does Spotlight/Clicker Capture work while another app is focused
- does local OSC/Companion control target the current OBS Program scene
- do embedded video and audio land in OBS reliably enough for beta
- does fallback mode remain usable if live attachment is unavailable

## Recommended Feedback To Collect

- Windows version
- OBS version
- PowerPoint version
- whether the plugin built and loaded
- whether `PPTBridge SK Slide` and `PPTBridge SK Presenter` appeared
- whether live capture attached
- whether PowerPoint resize lock worked
- whether multi-deck scene routing worked
- whether Spotlight/Clicker Capture worked
- whether local OSC/Companion worked
- whether audio landed in the OBS mixer
- whether presenter notes rendered
- whether fallback mode still worked
- OBS log file if anything failed
