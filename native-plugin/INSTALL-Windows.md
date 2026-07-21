# PPTBridge SK for OBS - Windows Install

## Download

Download and extract only:

`pptbridge-obs-windows-x64-v0.5.8.zip`

Optional integrity file:

`pptbridge-obs-windows-x64-v0.5.8.zip.sha256`

## Easy Install

1. Close OBS Studio.
2. Right-click the ZIP and choose **Extract All**.
3. Open the extracted folder and double-click `INSTALL.cmd`.
4. Allow administrator permission if Windows asks.
5. Start OBS and add `PPTBridge SK Slide` from **Sources > +**.
6. Select a PowerPoint file and click **Start / Restart PowerPoint Live Mode**.

The installer detects a normal OBS installation automatically. For portable OBS or a custom folder, run:

```bat
INSTALL.cmd "D:\Path\To\obs-studio"
```

Re-running `INSTALL.cmd` safely installs the new version over an older PPTBridge SK DLL. It closes only the selected OBS installation, not another portable OBS copy that may also be open.

## Recommended Show Setup

- Add `PPTBridge SK Slide` to the audience Program scene.
- Add `PPTBridge SK Presenter` to the stage/confidence-monitor scene for notes, next slide, timer, and cues.
- Keep **Lock OBS Output Size** selected. The PowerPoint window can then be resized or moved without changing the 1920x1080 OBS source.
- Enable **Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off** for a Logitech Spotlight or other presenter remote that sends `PageDown` and `PageUp`.
- Put each deck in its own OBS scene. Multiple PowerPoint live sessions may remain ready, while the clicker and OSC follow only the current Program scene.
- Leave **Route PowerPoint App Audio Through OBS** enabled on one PPTBridge Slide source per Program scene.

Normal keyboard input remains available to the operator. The global clicker hook captures only `PageDown` and `PageUp`; ordinary letters, numbers, `Space`, and left/right arrows are not taken from the focused application.

Extra Next presses on the final slide are ignored, so the presentation remains visible and the speaker can go back with Previous.

## Requirements

- Windows 10/11 x64
- OBS Studio 30 or newer, 64-bit
- Desktop Microsoft PowerPoint

Windows supports modern PowerPoint formats and legacy `.ppt`. PDF input is not enabled on Windows.

## Troubleshooting

If the plugin is missing after installation, close OBS and run `INSTALL.cmd` again. Confirm that the installer selected the same OBS folder you normally launch. Then open **OBS > Help > Log Files > View Current Log**, search for `PPTBridge SK`, and attach that log to a GitHub issue.

## Build The Public ZIP

After a clean Release build:

```powershell
cmake --build native-plugin/build-win-v058-clean-release --config Release
powershell -ExecutionPolicy Bypass -File native-plugin/scripts/make-windows-release.ps1 `
  -BuildDir native-plugin/build-win-v058-clean-release
```

The script creates the ZIP and matching `.sha256` file under `native-plugin/release`. The public ZIP intentionally contains only `INSTALL.cmd`, `README.txt`, the DLL, and two required locale files.
