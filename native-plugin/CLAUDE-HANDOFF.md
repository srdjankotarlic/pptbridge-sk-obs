# Claude Handoff: PPTBridge SK for OBS

Project path:

- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin`

Author / branding:

- The plugin is branded as **PPTBridge SK**
- The author's name should remain clearly visible as **Srđan Kotarlić**

## What Is Already Done

This is no longer just an OBS script idea. A real native macOS OBS plugin project now exists and **builds successfully**.

Implemented:

- Native OBS plugin CMake project
- Two real OBS source types:
  - `PPTBridge SK Slide`
  - `PPTBridge SK Presenter`
- Frontend hotkeys registered by the plugin:
  - next
  - previous
  - black screen
  - first
  - last
- Shared presentation registry so both sources can point to the same deck
- `.pptx -> PDF` conversion through LibreOffice
- Native PDF rendering through `PDFKit`
- Notes extraction from `.pptx` zip XML using `unzip` + `NSXMLDocument`
- macOS `.plugin` bundle output
- Locale resource copied into the built plugin bundle

## Current Build Status

This command succeeds:

```bash
cmake -S /Users/srdjankotarlic/Documents/New\ project/pptbridge-obs-plugin/native-plugin \
  -B /Users/srdjankotarlic/Documents/New\ project/pptbridge-obs-plugin/native-plugin/build \
  -DOBS_SOURCE_DIR=/Users/srdjankotarlic/Documents/New\ project/pptbridge-obs-plugin/native-plugin/third_party/obs-studio \
  -DOBS_APP_DIR=/Applications/OBS.app

cmake --build /Users/srdjankotarlic/Documents/New\ project/pptbridge-obs-plugin/native-plugin/build --config RelWithDebInfo
```

Built bundle:

- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/build/bundle/pptbridge-obs.plugin`

Installer artifacts:

- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/PPTBridge-Install.command`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/dist/PPTBridge-SK-for-OBS-Installer.pkg`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/release/PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/PUBLISHING.md`

Built bundle contents verified:

- binary exists
- `Info.plist` exists
- `Contents/Resources/locale/en-US.ini` exists

Installer status:

- `.command` installer exists and copies into the current user's OBS plugin folder
- `.pkg` installer is successfully generated
- `.pkg` is currently unsigned

Runtime status update:

- the earlier `compiled with newer libobs 32.1` mismatch was fixed by pinning `obs_module_ver()` to the installed OBS 32.0.3 API level
- after that fix, OBS no longer reported the libobs version mismatch
- OBS now loads the plugin and registers the slide/presenter source types during a normal launch
- a later startup crash was traced to `ConvertPptxToPdf()` in `presentation_document.mm`, specifically the old ARC-sensitive `NSString **` task output pattern
- that helper was rewritten to return `std::string` output safely, and failed loads no longer re-trigger every video tick
- the installed plugin bundle in `~/Library/Application Support/obs-studio/plugins/pptbridge-obs.plugin` has been replaced with this crash-fix build
- LibreOffice failures are now followed by a native Microsoft PowerPoint fallback exporter on macOS when PowerPoint is installed
- OBS runtime was verified in logs after load success with real decks from the Desktop test files
- user-local installs now strip quarantine, clean up the legacy Python script entry, and package a shareable release zip

Linked libraries checked with `otool -L`:

- `@rpath/libobs.framework/Versions/A/libobs`
- `@rpath/obs-frontend-api.dylib`
- Apple frameworks for Foundation, AppKit, PDFKit, CoreGraphics

## Build Dependencies Added During This Work

Installed locally:

- `cmake`
- `simde`

OBS source tree cloned for headers:

- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/third_party/obs-studio`

## Important Files

- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/CMakeLists.txt`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/cmake/FindOBS.cmake`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/src/plugin-main.mm`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/src/presentation_document.mm`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/src/source_slide.mm`
- `/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin/src/source_presenter.mm`

## Architecture Summary

### Source Types

There are two OBS source types:

- `pptbridge_slide_source`
- `pptbridge_presenter_source`

Both use the same shared document state when pointed to the same `.pptx`.

### Document Pipeline

`PresentationDocument` does this:

1. convert `.pptx` to PDF via LibreOffice
2. open the PDF with `PDFDocument`
3. extract notes/title text from the `.pptx` package XML
4. expose current slide state and render methods

### Rendering

Rendering is native, not browser-based:

- slide view renders the current page into a BGRA texture
- presenter view renders:
  - current slide
  - next slide preview
  - notes
  - timer
  - black-live badge

## What Is Not Verified Yet

These things are still worth testing on a second machine:

- opening OBS from a clean machine with only the `.pkg` installer
- confirming `PPTBridge SK` source names and hotkeys appear on another Mac exactly as expected
- checking whether OBS runtime resolves `@rpath` cleanly from the system plugin location on other machines
- optional signing/notarization before broad public release

## Likely Next Steps For Claude

### 1. Runtime test the installed crash-fix build

The latest rebuilt bundle is already installed at:

- `~/Library/Application Support/obs-studio/plugins/pptbridge-obs.plugin`

Then launch OBS and verify:

- OBS no longer crashes on startup with the saved PPTBridge scene present
- `PPTBridge SK Slide` appears in source picker
- `PPTBridge SK Presenter` appears in source picker
- the source preview shows a useful error message instead of crashing if conversion fails

### 2. Verify source behavior with a real PowerPoint

Inside OBS:

- add both sources
- point them to the same `.pptx`
- verify slide rendering
- verify presenter notes
- verify next/previous/black hotkeys
- specifically verify whether LibreOffice fails only on `CV_Miljana_Kotarlic (1).pptx` or on all `.pptx` files
- if LibreOffice still fails, consider a fallback exporter path such as Microsoft PowerPoint automation when PowerPoint is installed

### 3. Fix runtime issues if any

Most likely remaining runtime issues, if they happen:

- bundle install path
- `@rpath` resolution from plugin location
- locale loading
- LibreOffice path / conversion edge cases
- thread safety or redraw timing issues
- repeated retry storms are already fixed; do not reintroduce per-frame reload attempts after a failed conversion

### 4. Polish after runtime success

Good follow-up improvements:

- add a reload button / reload property action
- add better empty / loading / error states in OBS preview
- let the user explicitly choose which deck is the "active" hotkey-controlled presentation
- add optional dock or local control UI later
- add packaging script for easy release zip
- add screenshots and portfolio-ready README polish
- keep `PPTBridge SK` naming consistent across installers and release assets

## Things Claude Should Not Accidentally Regress

- Keep the plugin native. Do not revert back to browser-source-only architecture.
- Keep `Srđan Kotarlić` visible in metadata and docs.
- Keep both source types: audience slide and presenter view.
- Keep notes extraction if at all possible.
- Keep the buildable state that already works with the local toolchain.

## Quick Status Sentence

The native macOS OBS plugin project is now real and buildable; the next job is OBS runtime installation/testing and any final fixes needed so the sources appear and behave correctly inside the app.
