PPTBridge SK for OBS - Windows

Download only this file for Windows:
pptbridge-obs-windows-x64-v0.5.0-beta.1.zip

Install
1. Close OBS Studio.
2. Right-click the zip and choose Extract All.
3. Open the extracted folder.
4. Double-click INSTALL.cmd.
5. Allow administrator permission if Windows asks.
6. Start OBS Studio.
7. Add Source -> PPTBridge SK Slide.
8. Choose your PowerPoint file.

If OBS is portable or installed in a custom folder, run:
INSTALL.cmd "D:\Path\To\obs-studio"

How to use
- PPTBridge SK Slide shows and controls a PowerPoint deck inside OBS.
- Use START in the source properties to open PowerPoint live mode.
- Use STOP to close PowerPoint live mode.
- Live Mode keeps PowerPoint running and lets OBS capture the PowerPoint slideshow window.
- If OBS is still attaching to PowerPoint, PPTBridge keeps the last rendered slide visible instead of closing and reopening PowerPoint.
- PowerPoint files can be local files or network share files, for example \\server\share\show.pptx.
- Modern `.pptx` decks are best, but legacy `.ppt` decks can also open through PowerPoint live/export mode.
- Default beta hotkeys are:
  Next Slide: 2
  Previous Slide: 1
- For a stage clicker while using the rest of the computer, enable:
  Tools -> PPTBridge SK: Toggle Spotlight/Clicker Capture
- Default clicker capture uses PageDown/Right for next and PageUp/Left for previous.
- Plain typing keys such as letters, numbers, Space, Enter, Tab, and Backspace are never captured globally.
- Normal typing still works while the operator uses the computer.
- The clicker controls only visible PPTBridge sources in the current OBS Program scene.
- Decks that are not in Program do not advance.
- Hidden PPTBridge sources do not advance.

For multi-deck shows
- Put each deck in its own OBS scene.
- Put the scene you want the presenter to control into Program.
- The clicker, OBS hotkeys, and local OSC control the Program scene deck only.

Local OSC / Companion
- Local OSC listens on 127.0.0.1:57130 when enabled.
- Example: /pptbridge/next

Requirements
- Windows 10/11 64-bit.
- OBS Studio 64-bit.
- Microsoft PowerPoint installed for live PowerPoint mode.

If the plugin does not appear in OBS
1. Make sure OBS was closed during install.
2. Run INSTALL.cmd again.
3. Start OBS and check Sources -> + -> PPTBridge SK Slide.
4. If it still does not appear, open OBS Help -> Log Files -> View Current Log and send the log.

If a network PowerPoint file does not render
1. Make sure the Windows user can open the file in PowerPoint.
2. Use the normal Windows path if possible, for example \\server\share\show.pptx.
3. Click Reload in the source properties after changing the file.
4. Send the OBS log if OBS still shows a PPTBridge SK render message.

Note for non-English PowerPoint
- Some PowerPoint versions export slide images with localized names, for example Folie1.PNG.
- This Windows package detects those localized image names automatically.

Fixed in this Windows package
- Live Mode no longer closes and reopens PowerPoint when OBS capture needs a moment to attach.
- OBS capture uses the correct Windows PowerPoint window descriptor.
- The loading screen text now displays normal dots instead of broken characters.
