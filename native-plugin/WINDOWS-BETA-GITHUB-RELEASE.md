# PPTBridge SK for OBS v0.5.0-beta.1

**Windows Beta Plugin ZIP**

Created by **Srdjan Kotarlic**

This prerelease is for Windows OBS users who want to test PowerPoint live mode with a packaged 64-bit plugin and a simple installer. The stable public macOS release is the Apple Silicon `v0.4.7` release.

## Start Here

- Windows beta scope: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/WINDOWS-BETA-RELEASE.md
- Windows install guide: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/INSTALL-Windows.md
- Windows test checklist: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/WINDOWS-ALPHA-TESTING.md
- General FAQ: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md

## Included Asset

- `pptbridge-obs-windows-x64-v0.5.0-beta.1.zip`
- `pptbridge-obs-windows-x64-v0.5.0-beta.1.zip.sha256`

Download the Windows ZIP above, extract it, then double-click `INSTALL.cmd`.

## What Is New For Windows

- Native Windows `PPTBridge SK Slide` and `PPTBridge SK Presenter` source paths are aligned with the macOS feature model.
- The Windows download is now a small binary plugin ZIP with a double-click installer.
- Legacy `.ppt` decks can be selected and opened through the Windows PowerPoint path.
- PowerPoint live mode can be manual by default: OBS can open without immediately starting the slideshow.
- `START / RESTART - Open PowerPoint Live Mode` and `STOP - Stop PowerPoint Live Mode` are highlighted in source properties.
- `Auto Start PowerPoint When OBS Opens` restores automatic startup when wanted.
- `Close PowerPoint Slideshow When OBS Closes` can clean up the running slideshow.
- `PowerPoint Resize Behavior` defaults to `Lock OBS Output Size`, so shrinking the PowerPoint window should not shrink the OBS scene source.
- Multi-deck scene routing targets the PPTBridge source in the current OBS Program scene.
- Local OSC/Companion control targets the current Program scene.
- OBS hotkeys only fire while OBS is focused.
- Optional `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture` captures presenter remote keys such as `PageDown`/`Right` and `PageUp`/`Left`, routes the stage clicker to PPTBridge, and suppresses only those captured clicker keys from the focused app.
- Plain typing keys such as letters, numbers, `Space`, `Enter`, `Tab`, and `Backspace` are never captured globally, so the operator can still use the computer during the show.
- Presenter customization is included in the Windows renderer path.

## Known Beta Limits

- This is still beta software; test it on the target OBS/PowerPoint computer before a paid or live show.
- PDF input is not enabled on Windows yet.
- Audio capture may vary depending on OBS version and Windows capture support.

## Windows Validation Checklist

1. Extract `pptbridge-obs-windows-x64-v0.5.0-beta.1.zip`.
2. Double-click `INSTALL.cmd`.
3. Confirm both source types appear in OBS.
4. Add a PowerPoint deck to `PPTBridge SK Slide`.
5. Verify OBS does not auto-start PowerPoint unless `Auto Start PowerPoint When OBS Opens` is enabled.
6. Click `START / RESTART - Open PowerPoint Live Mode`.
7. Confirm the PowerPoint slideshow opens and OBS attaches the live show.
8. Resize the PowerPoint slideshow window and confirm OBS output stays filled with `Lock OBS Output Size`.
9. Click `STOP - Stop PowerPoint Live Mode`.
10. Test next/previous/first/last/black/reload buttons.
11. Test OBS hotkeys while OBS is focused, then type in another app and confirm normal typing does not move slides.
12. Enable Spotlight/Clicker Capture and test a clicker while another app is focused.
13. Test local OSC/Companion paths such as `/pptbridge/next`.
14. Create two OBS scenes with two different decks and verify each Program scene controls its own deck.
15. Test a deck with notes, click-builds, embedded video, and embedded audio.

## Feedback Wanted

Please report Windows version, OBS version, PowerPoint version, build errors if any, OBS log, whether the plugin loaded, whether live capture attached, whether resize lock worked, whether multi-deck routing worked, and whether clicker capture worked.
