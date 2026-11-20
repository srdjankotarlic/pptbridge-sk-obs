# PPTBridge SK v0.5.13 platform QA

Tested November 20, 2026.

## macOS Apple Silicon

An M1 Pro running macOS 27.2.1, OBS Studio 33.0.1 and desktop PowerPoint ran the release candidate in an isolated OBS configuration.

| Check | Result |
| --- | --- |
| Early preview while PPTX notes load | The v0.5.12 baseline returned to slide 1 and cleared Black Screen. The candidate kept slide 2 and Black Screen when notes finished. |
| PowerPoint and PDF static output | PDF/PPTX rendering, three PDF page shapes, rotated PDF pages, Presenter layouts, missing-file relinking, malformed inputs and cache replacement/recovery passed. The fixtures included filenames with spaces and Unicode. |
| Live control | Manual start, reattach, stop, auto start, restart, final-slide Next protection, Previous and Black Screen/restore passed in OBS. Source controls, focused hotkeys, two-deck Program routing, cue controls and 16 OSC status messages passed. |
| Stage Manager enabled | The baseline produced transparent slideshow frames while PowerPoint was in the background. The candidate displayed the current slide preview and followed navigation, including on the final page. |
| Stage Manager disabled | Real PowerPoint video produced 14 moving frame transitions in the test sample. OBS recorded live audio meter activity from the presentation. |
| Installer | The extracted ZIP installed successfully. Incomplete bundles and concurrent activation were rejected without modifying the prior copy. A forced activation failure restored the previous plugin. The packaged bundle passed signature and SHA-256 verification. |

OBS 32.2.2 hit the same Qt/CoreGraphics crash at startup on macOS 27.2.1 both
with PPTBridge and without it. Use OBS 33.0.1 or later on macOS 27. Stage Manager
can stay enabled for native PDF decks and static previews. When enabled, live
video and animations require PowerPoint in the foreground.

## Windows x64

The [Windows QA run](https://github.com/srdjankotarlic/pptbridge-sk-obs/actions/runs/44774585717)
tested the candidate on native Windows runners with OBS 32.0.2 and OBS 33.0.1.

- The DLL and smoke tests built with current MSVC using standard C++20 coroutines.
- The Windows PDF engine rendered all three pages and rejected a corrupt input.
- Each five-file ZIP installed and reinstalled into portable OBS. The installed DLL matched the extracted payload.
- Each installed DLL loaded through the corresponding libobs. Both source types reported missing files, relinked a Unicode path and cleared an optional missing background.
- Full OBS rendered Slide and Presenter, advanced through three distinct PDF pages and stayed on the last page after an additional Next.

The production Windows download remains v0.5.10. A Windows machine with
desktop PowerPoint is needed for the v0.5.13 live capture, media, animations
and clicker matrix. The runners did not exercise the corporate Windows install
policy or physical clicker hardware.

## Intel Mac

The x86-64 build and both sources' relink checks passed in OBS 33.0.1's libobs
under Rosetta. Full Intel OBS GUI startup and real Intel hardware validation
remain open.
