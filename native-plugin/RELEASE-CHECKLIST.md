# Release Checklist

## Before Publishing

- build the native plugin successfully
- run `./scripts/make-release.sh`
- confirm the release zip exists
- confirm the `.pkg` installer exists
- restart OBS and verify:
  - `PPTBridge SK Slide` appears
  - `PPTBridge SK Presenter` appears
  - hotkeys work
  - `Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off` appears and logs that it loaded PPTBridge hotkey bindings
  - with macOS permissions granted, a PageDown/PageUp presenter binding advances the current program deck while another app is focused
  - a sample `.pptx` loads
  - `Tools > PPTBridge SK: Local OSC Control On/Off` starts the local OSC listener
  - `send-osc.sh /pptbridge/next` moves the active program deck
  - Companion Generic OSC can send `/pptbridge/next` to `127.0.0.1:57130`
  - default/manual mode opens OBS without launching PowerPoint
  - `START / RESTART - Open PowerPoint Live Mode` opens PowerPoint if needed and starts the slideshow from the highlighted `PowerPoint Live Start / Stop` group
  - `Auto Start PowerPoint When OBS Opens` starts PowerPoint automatically
  - `Close PowerPoint Slideshow When OBS Closes` stops the slideshow when OBS quits
  - `PPTBridge SK Presenter` stays static and lightweight; live PowerPoint/video playback remains in `PPTBridge SK Slide`

## Assets To Upload

- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-apple-silicon.zip.sha256`

Upload only this canonical ZIP plus checksum. Do not add a second duplicate ZIP with a longer release-specific filename.

## GitHub Release

- create the repository
- push the code
- create the release tag that matches `native-plugin/CMakeLists.txt`
- create a GitHub Release
- paste the body from `GITHUB-RELEASE.md`
- upload the release assets

## OBS Forums

- create a new resource in the `OBS Studio Plugins` category on obsproject.com
- use the text from `OBS-FORUM-POST.md`
- attach or link the GitHub release
- add 2 screenshots:
  - clean slide source
  - presenter source with notes

OBS Forums / obsproject.com resources are the primary audience channel for this plugin. LinkedIn is secondary.

## After Publishing

- test the public download link
- post the GitHub release link in the OBS resource page
- save the forum URL for your portfolio
