PPTBridge SK for OBS - Windows x64
Version: v0.5.9

INSTALL IN A FEW CLICKS

1. Close OBS Studio.
2. Right-click the downloaded ZIP and choose Extract All.
3. Open the extracted folder.
4. Double-click INSTALL.cmd.
5. Allow administrator permission if Windows asks.
6. Start OBS Studio.

The installer finds a normal OBS installation automatically. For portable OBS
or a custom installation, run:

INSTALL.cmd "D:\Path\To\obs-studio"

FIRST PRESENTATION

1. In OBS Sources, click + and choose PPTBridge SK Slide.
2. Browse to a PDF, .pptx, .pptm, .ppsx, .potx, .potm, or legacy .ppt file.
3. PDF pages load directly. For a PowerPoint file, open source Properties and
   click Start / Restart PowerPoint Live Mode.
4. Add PPTBridge SK Presenter to a separate confidence-monitor scene if you
   want current slide, next slide, notes, timer, and cue list.
5. Click Stop PowerPoint Live Mode when the live session is no longer needed.

STAGE CLICKER WHILE THE OPERATOR USES THE COMPUTER

Enable Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off.

- PageDown moves to the next slide and PageUp moves to the previous slide.
- The clicker follows the PPTBridge deck in the current OBS Program scene.
- A deck that is only in Studio Preview does not receive the click.
- The clicker keys are swallowed, so they do not affect the operator's app.
- Letters, numbers, Space, Enter, Tab, Backspace, and normal Left/Right arrows
  remain available to the operator.

MULTIPLE PRESENTATIONS

- Put each deck in its own OBS scene.
- Start every deck that must be ready.
- Put the required scene in Program.
- Clicker, OBS controls, and local OSC follow the Program scene deck.
- Several PowerPoint live sessions can stay open at the same time.

LIVE PRODUCTION BEHAVIOR

- Resizing or moving the PowerPoint window does not change the OBS source size
  when Lock OBS Output Size is selected.
- PowerPoint menus, desktop, window borders, and scrollbars are removed from the
  OBS audience output.
- Extra Next presses on the final slide do not close the slideshow. Previous can
  return to earlier slides.
- Live animations, click builds, embedded video, and PowerPoint audio are kept.
- PowerPoint audio is routed only for the current Program source. If several
  PPTBridge Slide sources are intentionally visible in one Program scene, leave
  Route PowerPoint App Audio enabled on only one of them.
- The last good slide remains visible while a live window reattaches.
- Network paths such as \\server\share\show.pptx are supported when PowerPoint
  can open the file for the same Windows user.

CONTROLS

- Default OBS-focused hotkeys: 2 = Next, 1 = Previous.
- Local OSC can be enabled from Tools and listens on 127.0.0.1:57130.
- OSC commands: /pptbridge/next, /previous, /first, /last, /black, /reload.

REQUIREMENTS AND LIMITS

- Windows 10 or 11, 64-bit.
- OBS Studio 30 or newer, 64-bit.
- Desktop Microsoft PowerPoint is required for PowerPoint files and their live
  animations, video, and audio. It is not required for PDF files.
- PDF pages use the built-in Windows PDF engine; no separate PDF program is
  required. Password-protected PDFs are not supported.
- The DLL and installer are not code-signed yet. Windows may ask for
  confirmation before running the installer. Test every event deck on the
  production computer before show day.

IF THE PLUGIN DOES NOT APPEAR

1. Close OBS and run INSTALL.cmd again.
2. Confirm that you installed into the same OBS copy you normally start.
3. In OBS, open Help > Log Files > View Current Log.
4. Search for PPTBridge SK and include that log when reporting a problem.

The Windows download contains only this guide, INSTALL.cmd, the plugin DLL, and
the two small OBS locale files required by the plugin.
