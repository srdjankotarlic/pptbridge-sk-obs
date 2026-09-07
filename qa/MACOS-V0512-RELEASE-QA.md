# Apple Silicon v0.5.12 Release QA

Date: 2026-09-07. Environment: Apple M1 Pro, macOS 26.6.2, PowerPoint,
OBS Studio 32.2.2 / Qt 6.11.1, Stage Manager disabled.

## Decision

Approved for the Apple Silicon maintenance release on the tested configuration.
This follows up the unresolved findings in
[the earlier regression report](MACOS-PPT-PDF-REGRESSION-2026-09-07.md).
Windows remains on v0.5.10; Intel Mac remains on its previous beta. Neither was
built or tested here. This is not a claim that every presentation, Mac, or OBS
version is crash-free.

## Findings and Resolution

| Finding | Resolution and evidence |
| --- | --- |
| Wrong cached slides after same-path file replacement | Source and PDF SHA-256 fingerprints replace the mtime-only check. The final native regression replaced a 13-slide deck with a 17-slide deck preserving an older timestamp and correctly loaded 17 slides. |
| Damaged or unverified PDF cache | Corrupt PDF and malformed JSON manifest regenerated successfully. Verified legacy-cache migration passed. Unchanged reload took 340 ms in the final sample and did not rewrite the cached files. Old unverified caches export once after upgrade. |
| PowerPoint retained keyboard focus | Remember the application before startup, restore normal activation with a bounded fallback, and leave an operator-selected third app alone. Chrome remained foreground before and after all three final manual/automatic/restart live checks. |
| Tiny background slide / black capture | Reproduced with Stage Manager on using both ScreenCaptureKit and legacy Window Capture. Stage Manager off produced full-size live output while Chrome remained active. Added an in-plugin warning and setup guidance. This is a documented compatibility workaround, not support for reliable live capture with Stage Manager enabled. |
| OBS UI/accessibility/shutdown crashes | Updated the local OBS host from 32.1.1 / Qt 6.8.3 to official, signature-verified OBS 32.2.2 / Qt 6.11.1. Repeated UI queries, QA source creation/removal and orderly quit/relaunch cycles produced no new OBS crash reports after the update. Last observed crash was at 16:54:26 before it. No single upstream root cause was isolated. |
| Confusing input failures | Reject temporary PowerPoint lock files, display errors beside Browse, and support OBS missing-file relinking for both source types and optional Presenter backgrounds. Final invalid/missing-file tests passed. |
| Successful installer returned failure without a TTY | Only show the final Enter prompt for an interactive terminal. The actual extracted ZIP installer returned 0, copied the plugin and opened OBS. It refused replacement while OBS was running. |

## Final Validation

| Check | Result |
| --- | --- |
| Native build | arm64 RelWithDebInfo build passed; source guardrails and whitespace checks passed |
| Native corpus | 10 PPTX paths + 5 PDFs, 177 pages; every page rendered through Slide and Presenter. One PPTX is a sidecar fixture, not an additional independent presentation |
| Native runtime suite | 20/20 invocations passed: 15 render runs plus invalid input, missing-file recovery, registry, OSC controls and OSC feedback. Nine test compilations passed separately and are not counted as runtime tests |
| Render checks | Navigation bounds, blackout/restore, five Presenter layouts, three preview scales, custom background, cue state/export and invalid dimensions |
| Cache-specific regression | Six checks passed: older-timestamp replacement, unchanged reload, unchanged cache timestamps, truncated PDF, malformed manifest, verified legacy migration |
| Broad real-OBS run on candidate | Static hotkey callbacks, source/operator controls, reload, two-deck Program routing, Presenter customization, cue check/clear/export, and all 16 OSC status addresses passed before its final image-comparison assertion stopped the run |
| Focused final real-OBS continuation | 11 checks passed: manual start, reattach, manual stop, auto start, auto stop, restart, final-slide Next guard, Previous, blackout, restore and final stop |
| Live image checks | All three accepted startup captures had a fully green top test band (fraction 1.0), not PowerPoint chrome or a small Stage Manager thumbnail. Follow-up background captures remained full-size. Images were also visually inspected |
| Blackout checks | Mean RGB brightness exactly 0 while black; restored image identical to the settled preceding slide (full-resolution normalized difference 0) |
| Extracted release installation | Installer correctly refused a running OBS; after an orderly quit, installation returned 0 and OBS opened normally with v0.5.12 |
| Post-install sources | Six existing PPTBridge sources returned nonblank images: two PPTX Slide, three PDF Slide and one Presenter. Slide and Presenter samples were visually inspected |
| Package | One stable-name Apple Silicon ZIP plus its SHA-256 checksum. Archive contains the plugin, installer, START-HERE, README, Companion guide/template and OSC sender only; executable modes preserved; no private presentations, QA captures, duplicate ZIP or build files |
| Local cleanup | Temporary scenes/sources removed, Program and Preview restored to Scene 5. Existing scene collection preserved. NDI Main and Preview remained active at 1920x1080; no NDI settings changed |

Final live start to accepted full-size screenshot: 4.575 s manual, 3.260 s
automatic and 3.256 s restart on one 13-slide fixture. These include the test's
status polling and screenshot overhead, not a general startup guarantee.
Final post-install OBS sample: 60 FPS, approximately 9.9% CPU, 624 MB memory,
0 output-skipped frames / 4,687 output frames and 12 render-skipped / 4,827
rendered frames. This is a short observation, not a long-session performance
benchmark.

## Test Failures Kept Visible

The broad harness was not recorded as a complete pass. Its 32x18 mean-difference
cutoff classified two visibly different text slides on the same green background
as identical. A rerun encountered its OBS-focused hotkey precondition while
another application was active. The final focused continuation used authoritative
slide/live/black feedback, settled full-resolution image comparisons and brightness
checks. It did not disable or silently mark the hotkey assertions successful.
The successful candidate broad run supplies the earlier focused-hotkey evidence.

## Limits

- Tested upgrade of an existing Mac installation, not a pristine Mac or every
  Gatekeeper interaction. The plugin is ad-hoc signed, not Developer ID signed
  or notarized. The separately updated OBS application is notarized.
- Build deployment target remains macOS 12.0. Test linking reports that current
  OBS libraries target macOS 13.0. Older macOS/OBS combinations were not run;
  the tested macOS 26 configuration requires the newer OBS guidance above.
- No physical Spotlight clicker, separate Companion computer, external NDI
  receiver, multi-hour soak or fresh embedded-audio/video edge-case matrix in
  this follow-up. The corpus contains no embedded-media fixtures.
- Background live capture requires Stage Manager off. The installer does not
  change that preference or update OBS automatically. Static PDF/PPTX output
  does not require changing Stage Manager.
- The screenshot assertions check sampled ready frames, not every frame during
  startup or all possible slide aspect ratios, Spaces and display layouts.

## Artifact Identity

ZIP SHA-256:
`c1db6f7c39544ca71af6023c07ac4fbd5bdcc7d0d9bb7b8e8e4e45e7a7625aee`

Installed and extracted executable SHA-256, identical:
`5dd0eac6adefdffbda18eff489f65cd214d4a0edd6e11d1e4f62620b547c694f`

`codesign --verify --deep --strict` passed for the packaged bundle.
Private fixtures and screenshots remain outside Git. Local evidence is under
`/tmp/pptbridge-v0512-native-final`, `/tmp/pptbridge-v0512-package-test` and
`/tmp/pptbridge-obs-update-20260907/v0512-live-final`; macOS may remove temporary
files later.
