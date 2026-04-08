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

## Assets To Upload

- `PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
- `PPTBridge-SK-for-OBS-Installer.pkg`

## GitHub Release

- create the repository
- push the code
- create tag `v0.1.0`
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
