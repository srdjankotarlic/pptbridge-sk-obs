# PPTBridge SK for OBS v0.2.0-beta1

**Windows Beta Preview**

Created by **Srdjan Kotarlic**

This release is the first public Windows beta preview of `PPTBridge SK`.

It is intentionally published as a **beta** and **not** as a final Windows installer release yet.

## What It Is

`PPTBridge SK` is an OBS plugin project built around a conference-style PowerPoint workflow:

- `PPTBridge SK Slide` for the clean program feed
- `PPTBridge SK Presenter` for notes, next slide preview, and timer

The current stable public release path is still macOS-first, but this beta preview package is meant to move the Windows version into real-world validation.

## What The Windows Beta Is Designed To Do

- load PowerPoint files directly from OBS source properties
- expose `PPTBridge SK Slide` and `PPTBridge SK Presenter` as real OBS source types
- prefer a true live PowerPoint slideshow path for animations, click-builds, and embedded media
- keep slide navigation under OBS hotkeys
- render presenter notes, next-slide preview, and timer
- attempt to attach the live PowerPoint slideshow window into OBS
- attempt to attach PowerPoint audio into OBS through the live path or Windows process-audio fallback
- fall back to exported slides plus extracted embedded media when the live path is unavailable

## Important Beta Note

This Windows package is currently a **source/beta validation pack**, not a one-click installer.

It is being published so the Windows implementation can be tested, improved, and hardened on real Windows OBS systems.

## Current Known Limits

- not yet runtime-proven across multiple real Windows machines
- not yet packaged as a stable Windows installer release
- PDF input is not enabled in this Windows beta path
- exact live audio ownership can still vary depending on OBS build and Windows capture support

## Included Windows Beta Asset

- `PPTBridge-SK-Windows-Beta-v0.2.0-beta1-source.zip`

## Best Use Right Now

Use this beta if you want to help validate:

- source registration in OBS
- live slideshow capture
- Windows PowerPoint animation behavior
- embedded video/audio handling
- presenter notes rendering
- fallback behavior when live attach is unavailable

## Feedback Wanted

If you test this Windows beta, feedback is especially helpful on:

- Windows version
- OBS version
- whether the plugin built and loaded
- whether the slide and presenter sources appeared
- whether animations matched PowerPoint
- whether video rendered
- whether audio landed in the OBS mixer
- whether presenter notes rendered correctly
- OBS logs if anything failed
