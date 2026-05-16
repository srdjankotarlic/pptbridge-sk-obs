# PPTBridge SK for OBS v0.5.0-beta.1

**Windows Beta Source Validation Pack**

Created by **Srdjan Kotarlic**

This prerelease is for Windows build and runtime validation. The stable public user release is still the macOS `v0.4.3` release.

## Start Here

- Windows beta scope: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/WINDOWS-BETA-RELEASE.md
- Windows test checklist: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/WINDOWS-ALPHA-TESTING.md
- Windows Codex handoff: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/native-plugin/WINDOWS-CODEX-HANDOFF.md
- General FAQ: https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/main/FAQ.md

## Included Asset

- `PPTBridge-SK-Windows-Beta-v0.5.0-beta.1-source.zip`

This is a source package, not a final Windows installer. Build it on a Windows OBS machine, test it, and only publish a Windows binary after the checklist passes.

## What Is New For Windows

- Native Windows `PPTBridge SK Slide` and `PPTBridge SK Presenter` source paths are now aligned with the macOS feature model.
- PowerPoint live mode can be manual by default: OBS can open without immediately starting the slideshow.
- `START - Open PowerPoint / Start Live Mode` and `STOP - Stop PowerPoint Live Mode` are highlighted in source properties.
- `Auto Start PowerPoint When OBS Opens` restores automatic startup when wanted.
- `Close PowerPoint Slideshow When OBS Closes` can clean up the running slideshow.
- `PowerPoint Resize Behavior` defaults to `Lock OBS Output Size`, so shrinking the PowerPoint window should not shrink the OBS scene source.
- Multi-deck scene routing targets the PPTBridge source in the current OBS Program scene.
- Local OSC/Companion control targets the current Program scene.
- OBS hotkeys only fire while OBS is focused.
- Optional `Tools > PPTBridge SK: Toggle Spotlight/Clicker Capture` can capture common presenter keys globally, route a stage clicker to PPTBridge, and suppress those keys from the focused app.
- Presenter customization is included in the Windows renderer path.

## Known Beta Limits

- Windows runtime is not yet confirmed by the Mac development machine.
- PDF input is not enabled on Windows yet.
- Audio capture may vary depending on OBS version and Windows capture support.
- There is no one-click Windows installer yet.

## Windows Validation Checklist

1. Build the plugin on Windows.
2. Install `pptbridge-obs.dll` into OBS.
3. Confirm both source types appear in OBS.
4. Add a PowerPoint deck to `PPTBridge SK Slide`.
5. Verify OBS does not auto-start PowerPoint unless `Auto Start PowerPoint When OBS Opens` is enabled.
6. Click `START - Open PowerPoint / Start Live Mode`.
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
