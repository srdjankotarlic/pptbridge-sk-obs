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
  - a sample `.pptx` loads
  - `Tools > PPTBridge SK: Toggle Local OSC Control` starts the local OSC listener
  - `send-osc.sh /pptbridge/next` moves the active program deck
  - Companion Generic OSC can send `/pptbridge/next` to `127.0.0.1:57130`
  - default/manual mode opens OBS without launching PowerPoint
  - `Open PowerPoint / Start Live Mode` opens PowerPoint if needed and starts the slideshow
  - `Auto Start PowerPoint When OBS Opens` starts PowerPoint automatically
  - `Close PowerPoint Slideshow When OBS Closes` stops the slideshow when OBS quits

## Assets To Upload

- `PPTBridge-SK-for-OBS-v0.4.1-macOS-Apple-Silicon.zip`
- `PPTBridge-SK-for-OBS-v0.4.1-macOS-Intel.zip`
- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-intel.zip`
- `PPTBridge-SK-for-OBS-Installer.pkg`

## GitHub Release

- create the repository
- push the code
- create tag `v0.4.1`
- create a GitHub Release
- paste the body from `GITHUB-RELEASE.md`
- upload the release assets

## OBS Forums

- create a new resource in the `OBS Studio Plugins` category
- use the text from `OBS-FORUM-POST.md`
- attach or link the GitHub release
- add 2 screenshots:
  - clean slide source
  - presenter source with notes

## After Publishing

- test the public download link
- post the GitHub release link in the OBS resource page
- save the forum URL for your portfolio
