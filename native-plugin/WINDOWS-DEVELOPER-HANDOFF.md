# Windows Developer Handoff

Use this note when maintaining the stable Windows release on a Windows computer.

```text
We are maintaining PPTBridge SK for OBS on Windows.

Workspace:
<choose the local checkout of srdjankotarlic/pptbridge-sk-obs>

First read:
native-plugin/WINDOWS-RELEASE.md
native-plugin/WINDOWS-TESTING.md
native-plugin/WINDOWS-PORT.md

Important context:
- Windows x64 is a stable v0.5.9 release platform. Do not publish a replacement asset until the full release checklist passes.
- Do not change the macOS stable release files unless a Windows compile fix truly requires a shared file change.
- The Windows code matches the macOS v0.5.8 production workflow where possible:
  - PPTBridge SK Slide and PPTBridge SK Presenter OBS sources
  - manual START and STOP PowerPoint live controls
  - optional Auto Start PowerPoint When OBS Opens
  - optional Close PowerPoint Slideshow When OBS Closes
  - Lock OBS Output Size so resizing PowerPoint does not shrink OBS output
  - Follow PowerPoint Window Size as the intentional alternate mode
  - multi-deck scene routing by current OBS Program scene
  - OBS-focused hotkeys
  - optional Spotlight/Clicker Capture
  - local OSC/Companion control on 127.0.0.1:57130
- PDF input uses the built-in Windows PDF engine. Test both PDF and PowerPoint decks.

Start by running:
git status
cmake --version
where cl
where cmake

Then configure and build:
cmake -S native-plugin -B native-plugin/build-win -DOBS_SOURCE_DIR=C:\path\to\obs-studio -DOBS_APP_DIR="C:\Program Files\obs-studio"
cmake --build native-plugin/build-win --config RelWithDebInfo

If CMake needs OBS paths, discover the installed OBS location and the OBS source/header tree. Do not guess silently; report the exact missing variable or path.

After build:
1. Install the DLL into a test/portable OBS if possible:
   C:\Program Files\obs-studio\obs-plugins\64bit\pptbridge-obs.dll
   C:\Program Files\obs-studio\data\obs-plugins\pptbridge-obs\...
2. Open OBS and confirm these sources appear:
   PPTBridge SK Slide
   PPTBridge SK Presenter
3. Test real PDF and PowerPoint decks using native-plugin/WINDOWS-TESTING.md.

Must verify:
- OBS does not auto-start PowerPoint unless Auto Start is enabled.
- START opens PowerPoint/live slideshow.
- STOP stops the slideshow.
- Resizing the PowerPoint window does not resize OBS output when Lock OBS Output Size is selected.
- Follow PowerPoint Window Size intentionally follows the current PPT window shape.
- Two OBS scenes with two different PPT decks each control the correct deck.
- OBS hotkeys only work while OBS is focused.
- Spotlight/Clicker Capture works while another app is focused and suppresses the clicker key from the focused app.
- Local OSC /pptbridge/next reaches the current Program scene deck.
- PDFs load without launching PowerPoint and support navigation, Presenter, final-page protection, clicker, and OSC.
- Multiple PDFs and PowerPoint decks can coexist in separate OBS scenes.

If everything passes, create the minimal Windows zip containing:
- obs-plugins/64bit/pptbridge-obs.dll
- data/obs-plugins/pptbridge-obs/locale/en-US.ini
- data/obs-plugins/pptbridge-obs/locale/en-GB.ini
- INSTALL.cmd
- README.txt

Name it:
pptbridge-obs-windows-x64-v0.5.9.zip

Also create:
pptbridge-obs-windows-x64-v0.5.9.zip.sha256

Report exactly what passed, what failed, and include OBS log paths. Keep known limits visible: desktop PowerPoint is required for PowerPoint files, password-protected PDFs are unsupported, and the installer is not code-signed yet.
```

## Notes For The Mac Development Machine

Windows assets must be compiled and runtime-tested in real Windows OBS before publishing. A macOS-only build or source inspection is not enough.
