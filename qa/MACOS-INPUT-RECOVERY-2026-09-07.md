# macOS Input Recovery QA - 2026-09-07

## Scope and Result

Local repair based on `origin/main` at `bdbcc88` (v0.5.11). No release, tag,
or push was made. The modified Apple Silicon bundle was installed locally and
its new error message was verified in the running OBS Properties dialog.
Windows and release packaging were not changed or tested.

The reported blank sources had two concrete configuration causes: two sources
selected a 165-byte PowerPoint owner/lock file beginning with `~$`, and another
selected a deck at its old Desktop location after the folder moved to Documents.
The sources were relinked to the real decks after backing up the scene files.

## Changes

- Reject temporary PowerPoint lock files before attempting conversion; identify
  the real filename the operator should select.
- Explain how to recover when a presentation has moved or been renamed.
- Show load errors directly below Browse instead of only in the long status
  text; distinguish an unavailable presentation from an idle/empty cue list.
- Refresh open Properties when an asynchronous load finishes or fails.
- Register the OBS missing-files callback for macOS Slide and Presenter sources,
  including an optional presenter background image. Relinking updates the right
  setting; clearing a missing background leaves the presentation path intact.

## Environment

- Apple M1 Pro, macOS 26.6.2, OBS Studio 32.1.1, Microsoft PowerPoint installed.
- Native arm64 RelWithDebInfo build, macOS deployment target 12.0.
- Local ad-hoc bundle signature verified. Not Developer ID signed/notarized.
- Studio Mode enabled; existing DistroAV 6.2.1 Main and Preview outputs active.
- No recording or streaming session started by these tests.

## Verified

| Check | Evidence / Result |
| --- | --- |
| Build | `cmake --build native-plugin/build --parallel 4` passed |
| Source checks | `git diff --check` and `native-plugin/tests/audit_guardrails.py` passed |
| Invalid input | `invalid_input_smoke.mm`: 8 rejection/hint checks passed, including corrupt PPTX/PDF, missing files, unsupported type, empty path and lock file |
| Missing files callbacks | `missing_file_smoke.mm`: both Slide and Presenter reported the missing deck/background, relinked the deck, cleared only the background, loaded a 16-page PDF and cleared the error |
| Open Properties recovery | Running OBS displayed the lock-file explanation at the top; changing to a valid PDF changed status to ready, slide 1/16, and removed the error without closing the dialog |
| Static sources | PPTX Slide, PDF Slide and Presenter rendered nonblank screenshots |
| Static navigation | Hotkey requests, source buttons and operator buttons advanced/restored slides; First, Last and Reload checks passed |
| Program routing | With two different decks, the non-target deck stayed unchanged while commands went to Program |
| Cue controls | Check/uncheck/clear, cue export and OSC cue-status assertions passed |
| OSC feedback | All 16 expected status addresses received, including loading/error, deck/source names and cue state |
| Presenter customization | Background image, layout and cue-list settings changed rendered output |
| Live lifecycle | Manual start, reattach, manual stop, auto-start, auto-start stop and restart produced the expected status/output in the broad runtime test |
| End of deck | Next on the final slide retained both its slide index and active Live mode |
| Previous from final slide | Correct preceding slide verified by OSC status and inspected screenshot |
| Blackout | Black output had mean grayscale brightness 0; toggling off restored the previous slide |
| Stop after navigation | Returned to loaded, nonblank cached output |
| Test cleanup | Disposable sources/scenes removed; original Program and Preview Scene 6 restored; existing NDI Main and Preview remained active |

## Timing Samples

These are observations on this laptop and these decks, not a general speed
guarantee or a claimed conversion optimization.

- Corrected cached 17-slide deck: preview 16 ms, complete load 384 ms.
- Corrected cached 13-slide deck: preview 6 ms, complete load 209 ms.
- Isolated 13-slide PPTX copied to a new path: complete feedback-ready load
  4.34 seconds on the first run and 3.19 seconds on the follow-up run.
- Isolated Live start to ready feedback: 1.96 and 2.56 seconds.

## Test Caveats and Remaining Coverage

The broad `obs-websocket-smoke.mjs` run exited nonzero at its last-to-previous
image comparison. The saved images visibly showed different slides, but both
had the same green background: the 32x18 mean pixel distance was 0.00795, below
the test's fixed 0.01 cutoff. Earlier checks completed; the whole script is NOT
recorded as an end-to-end pass. Its file was not changed because the original
checkout has separate user work on that test.

A focused continuation used slide-status assertions and full-resolution pixel
checks. Its first attempt sampled the presentation's animated transition too
early; the successful run waited for a settled frame before testing blackout
and restore. All seven focused checks then passed. This does not establish
latency limits for every deck's own animations.

The missing-files native test is headless. It explicitly applies OBS's deferred
source update because there is no video loop. It validates the real registered
callbacks and loaded document state, but not the visual OBS missing-files dialog.
The open Properties recovery was tested separately in real OBS.

Not validated here: physical Spotlight hardware, a separate Companion computer,
external NDI reception, embedded audio/video edge cases, long-session soak,
other Macs, Windows, or a clean-machine installer run. A relaunch during setup
showed OBS's unsafe-shutdown prompt after an immediate quit/reopen; no new OBS
crash report was found, so clean shutdown is not claimed as a passed test.

OBS remained responsive. The post-test sample was about 59 FPS and 9.7% CPU,
with 784 render-skipped frames out of 51,185 over the mixed test session. This is
not a zero-frame-drop benchmark; capture, transitions and existing NDI outputs
were all present.

## Local Evidence

Client presentation screenshots stay outside the repository.

- `/tmp/pptbridge-runtime-20260907/`: broad-run screenshots.
- `/tmp/pptbridge-focused-runtime-20260907/`: focused screenshots and results.json.
- `/tmp/pptbridge-scenes-before-recovery-20260907/`: pre-edit scene backup.
- `/tmp/pptbridge-obs-v0511-before-recovery-20260907.plugin`: previous installed bundle.
- Installed executable SHA-256:
  `1102db6098ac22b28f281804592c289951ad2ed5bc2c0834b5c719a57ca304dc`.

Temporary evidence can be removed by macOS; the source fixes and native tests
are tracked on the local recovery branch. No user presentation assets were
added to Git.
