# Contributing

PPTBridge SK is a live-production OBS plugin, so changes should favor reliability, clear setup, and predictable show behavior.

## Current Release Tracks

- macOS stable: public user releases and ZIP installers
- Windows beta: source validation and runtime testing

Please keep these tracks separate when possible. A Windows compile fix should not change macOS behavior unless the shared code truly requires it.

## Before You Start

1. Read [README.md](README.md).
2. Read [BUILDING.md](BUILDING.md) for local build commands.
3. For user-facing behavior, read [SETUP-GUIDE.md](SETUP-GUIDE.md).
4. For Windows work, read [native-plugin/WINDOWS-BETA-RELEASE.md](native-plugin/WINDOWS-BETA-RELEASE.md).

## What Makes A Good Pull Request

- One focused change per PR.
- Clear description of the workflow being improved.
- Notes on macOS, Intel, Apple Silicon, or Windows impact.
- Test notes from OBS when the change affects runtime behavior.
- Screenshots or short recordings for UI, capture, or presenter layout changes.

## Test Notes To Include

For macOS runtime work:

- macOS version
- Apple Silicon or Intel
- OBS version
- PowerPoint version
- deck type, `.pptx` or `.pdf`
- whether live mode, cached mode, clicker capture, OSC, or Companion was tested

For Windows beta work:

- Windows version
- OBS version
- PowerPoint version
- whether the plugin built
- whether OBS loaded the DLL
- whether `PPTBridge SK Slide` and `PPTBridge SK Presenter` appeared
- whether START/STOP, resize lock, multi-deck routing, clicker capture, and OSC were tested

## Code Style

- Follow the existing native plugin style.
- Keep user-facing labels clear and production-friendly.
- Avoid unrelated refactors in release-prep PRs.
- Keep docs in sync when behavior changes.

## Reporting Security Or Private Production Details

Do not attach private client decks, passwords, OBS WebSocket passwords, or sensitive show details to public issues. Use a minimal sample deck whenever possible.
