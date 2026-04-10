# PPTBridge SK Windows Beta Preview

**Author:** Srdjan Kotarlic

This is the first serious Windows beta preview for `PPTBridge SK`.

It is not presented as a final Windows installer release yet. It is a source/beta package prepared for validation on a real Windows OBS machine.

## What This Windows Beta Is Meant To Do

- register `PPTBridge SK Slide` and `PPTBridge SK Presenter` as real OBS source types
- load a PowerPoint file directly from source properties
- prefer true live PowerPoint slideshow behavior for animations, click-builds, and embedded media
- keep slide navigation under OBS hotkeys
- render a dedicated presenter view with notes, next-slide preview, and timer
- attach PowerPoint slideshow video into OBS when the live capture path hooks correctly
- attempt to bring PowerPoint audio into OBS through the live window path or Windows process-audio fallback
- fall back to exported slide rendering plus extracted embedded media if the live path is not ready

## What The Beta Pack Includes

- current Windows-oriented native plugin source tree
- Windows testing checklist
- current docs and release metadata

## Honest Current Limits

- this Windows beta still needs runtime proof on a real Windows OBS machine
- it is not yet a one-click Windows installer
- PDF input is not enabled in this Windows beta path
- exact audio ownership can still vary by OBS build and Windows capture support available on that machine

## Best Current Usage Goal

Use this beta on a Windows test machine to answer these questions:

- do the two source types appear in OBS
- does live slideshow capture attach correctly
- do animations and click-builds behave like real PowerPoint
- do embedded video and audio land in OBS reliably
- does fallback mode remain usable if live attachment is unavailable

## Recommended Feedback To Collect

- Windows version
- OBS version
- whether the plugin built and loaded
- whether `PPTBridge SK Slide` and `PPTBridge SK Presenter` appeared
- whether live capture attached
- whether audio landed in the OBS mixer
- whether presenter notes rendered
- whether fallback mode still worked
- the OBS log file if anything failed
