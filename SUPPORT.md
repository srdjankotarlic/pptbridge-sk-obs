# Support

Thanks for testing PPTBridge SK. The fastest way to get a useful answer is to include enough show and system context in the first message.

## Before Opening An Issue

1. Install the newest stable macOS release from [GitHub Releases](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest).
2. Restart OBS normally, not Safe Mode.
3. Try `Reload Presentation` from the PPTBridge source properties.
4. If using PowerPoint live mode, confirm Microsoft PowerPoint can open the deck normally.
5. Check the current OBS log:
   `Help > Log Files > View Current Log`

## What To Include

Please include:

- PPTBridge SK release, for example `v0.4.5`
- macOS or Windows version
- Mac type, for example Apple Silicon or Intel
- OBS Studio version
- PowerPoint version, if using `.pptx`
- deck type, `.pptx` or `.pdf`
- whether you are using live PowerPoint mode or cached/PDF mode
- whether you are using hotkeys, clicker capture, Companion, OSC, or source buttons
- exact steps that reproduce the issue
- screenshots or a short screen recording when visual layout is the issue
- OBS log lines containing `PPTBridge SK`

## Good Bug Report Shape

```text
PPTBridge release:
OS:
OBS version:
PowerPoint version:
Deck type:
Source used: PPTBridge SK Slide / PPTBridge SK Presenter
Control method: hotkeys / clicker capture / Companion / OSC / buttons

What happened:
What I expected:
Steps:
1.
2.
3.

OBS log:
```

## Where To Ask

- Bugs: [open a bug report](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/new?template=bug_report.md)
- Feature ideas: [open a feature request](https://github.com/srdjankotarlic/pptbridge-sk-obs/issues/new?template=feature_request.md)
- Windows beta results: include the checklist from [native-plugin/WINDOWS-ALPHA-TESTING.md](native-plugin/WINDOWS-ALPHA-TESTING.md)

## Security

Do not post private decks, client names, passwords, OBS WebSocket passwords, or sensitive event details publicly. If a deck is needed to reproduce a bug, make a minimal sample deck that shows the same problem.
