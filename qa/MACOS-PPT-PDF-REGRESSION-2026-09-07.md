# macOS PPTX/PDF regression QA - 2026-09-07

Follow-up: [v0.5.12 release QA](MACOS-V0512-RELEASE-QA.md) records the later
cache/focus fixes, OBS update and Stage Manager compatibility workaround.
The observations below describe the earlier run and are retained as history.

## Decision

The cache-fix build passed the completed native and OBS functional suites. It is
installed locally, but this run is **not a release approval**. Visual inspection
found an unclean initial live frame despite the functional suite passing. OBS
also crashed during UI/accessibility inspection, source cleanup and later quits.
The cause of those crashes remains unresolved. No GitHub release or push was
performed.

Environment: Apple M1 Pro, macOS 26.6.2, OBS 32.1.1, PowerPoint, arm64 build.
Base: `bdbcc88` (v0.5.11) plus local input-recovery commit `e950339` and this patch.
Only copies of the user's presentation fixtures were used for destructive tests.

## Confirmed Bug And Fix

The macOS PDF cache previously trusted `PDF modification time >= PPTX modification
time`. Replacing a deck at the same path with another file preserving an older
timestamp reused the wrong PDF. Reproduction: 13-slide deck replaced by a
17-slide deck, then Reload still returned 13 slides.

The cache now records SHA-256 fingerprints for the source PPTX and exported PDF
in an atomically written JSON manifest. Unverified old caches and damaged PDFs
are regenerated. A source changed during export is not committed as a verified
cache. Verified legacy caches can still be migrated. Hashing is streamed in
64 KiB chunks on the loading worker, not on the OBS UI thread.

The new `native-plugin/tests/cache_replacement_smoke.mm` test passed:

- Same-path replacement with an older timestamp: 13 -> 17 slides.
- Unchanged reload: 319 ms for the 17-slide fixture, including notes/metadata.
- Cached PDF and manifest timestamps remain unchanged on that reload.
- Truncated cached PDF: automatic regeneration.
- Malformed manifest (JSON array rather than object): automatic regeneration.
- Verified legacy cache: migration and reuse.

First load after upgrading from an unverified cache exports once. This is a
correctness tradeoff, not a promise that every cold PPTX loads instantly.

## Completed Coverage

| Test | Result and limits |
|---|---|
| Build | arm64 RelWithDebInfo, macOS deployment target 12.0; passed |
| Native input matrix, rerun after cache fix | 10 PPTX + 5 PDF paths, 177 total pages; all loaded and rendered. One PPTX is a sidecar fixture, not an additional independent presentation |
| Native render checks | Every page rendered through Slide and Presenter; navigation bounds, blackout/restore, 5 presenter layouts x 3 preview scale modes, backgrounds, cue check/clear/export, invalid dimensions |
| Native test runner | 20 runtime invocations passed: 15 render tests plus invalid-input, missing-file, registry, OSC control and OSC feedback. 9 test builds also passed; do not count builds as runtime tests |
| Native live matrix, before cache fix | 12 invocations passed: rapid start/stop ordering, live navigation on all 10 PPTX fixtures, two simultaneous decks. Native PowerPoint control, not end-to-end capture for all 10 decks |
| Real OBS PDF matrix, before cache fix | All 5 PDFs, every page, first/last boundaries, blackout/restore, cue toggle/clear and reload |
| Real OBS stress, before cache fix | 100 Next + 100 Previous OSC commands, 30 path replacements, missing-file recovery, 4 Presenter output dimensions |
| Real OBS final suite, installed cache fix | Passed: focused Next/Previous hotkey callbacks, source/operator buttons, reload, Program/Preview deck isolation, Presenter customization, cue export and check/clear |
| OSC feedback in final suite | All 16 expected status addresses received, 864 messages, manual send plus live/loading/black/cue-state assertions passed |
| Real OBS live capture in final suite | Manual start, reattach, stop, automatic start, stop, restart, last-slide Next guard, Previous, blackout/restore, return to static output passed on one 13-slide PPTX. Visual inspection separately found a transient title bar/inset at startup; not a clean-frame approval |
| Installer | Refused to replace plugin while OBS was running; installed successfully after OBS closed, then opened OBS normally. Existing-install upgrade, not a pristine Mac/Gatekeeper test |
| Bundle | Installed arm64 executable, `codesign --verify --deep --strict` passed. Ad-hoc signature only; not Apple notarization |
| Cleanup | QA sources/scenes removed. Program restored to Scene 6, Preview to Scene 5. NDI Main/Preview outputs remained enabled; no receiver-side NDI test |
| Static guardrails | `python3 native-plugin/tests/audit_guardrails.py` and `git diff --check` passed |

Post-fix native first-preview timings on disposable paths: PDFs 65-71 ms;
cold PPTX 2.74-8.59 seconds. These are native document timings, not guaranteed
end-to-end OBS UI latency. In the final OBS log the cached 13-slide PPTX became
available in 5 ms and completed notes/metadata in 211 ms.

## Open Findings

### OBS UI/accessibility crashes

Seven macOS OBS reports exist for this afternoon, including earlier input-recovery
testing. Captured times: 15:35:50, 15:58:08, 16:15:04, 16:21:41, 16:30:40,
16:48:20 and 16:54:26 local.
The first two reports became available after the earlier QA inspection; the
earlier report's observation that no new report was visible is not a clean-crash
bill of health for the entire afternoon.

Six faulting stacks have Chromium Embedded Framework + Objective-C forwarding
and either `libqcocoa.dylib + 515284` during autorelease cleanup or accessibility
notifications during a scene-list change. Another fails in AppKit accessibility
focused-element lookup. No PPTBridge frame was identified on these faulting
stacks. This does not exclude earlier memory corruption or establish causality.

There are similar user reports in the OBS tracker:
[CEF crash report #13624](https://github.com/obsproject/obs-studio/issues/13624).
[Report #13505](https://github.com/obsproject/obs-studio/issues/13505) was closed
because the maintainers rejected the AI-generated report, not because they
confirmed or fixed its proposed cause. Neither is proof of our crash's cause.

The successful functional suite ran in the session started at 16:32:05. It used
WebSocket and source screenshots without further accessibility-tree reads during
scene creation/removal. Later quit attempts again crashed, so completion of that
suite does not establish shutdown stability. A controlled comparison without PPTBridge and with another
supported OBS/Qt build is still needed. OBS, Browser and DistroAV binaries or
permissions were not replaced/disabled to conceal this result.

### Initial Live Frame

`full-obs/slide-a-live.png` contains a PowerPoint title bar and a black left inset
at the beginning of a live restart. Later manual-live and final-slide frames are
clean. Nonempty-frame and image-difference assertions did not catch this defect.

A prototype that waited for capture dimensions to match the crop filter passed
seven headless cases, but did not solve the real OBS startup artifact. Its OBS
run failed the reattach visual comparison because the initial frame and clean
reattached frame differed. A later fixture-specific top-pixel assertion was not
reached. The prototype and its unit test were removed; no changes to
`source_slide.mm` are retained. A reliable capture-readiness fix and visual
regression test are still needed.

### Focus Restoration

The final OBS log contains three warnings that the previous application could
not regain focus after preparing the PowerPoint slideshow for capture. Capture
and OSC navigation passed, but automatic focus restoration is not verified as
reliable on this Mac. This requires a separate focused reproduction and fix.

### Remaining Coverage

- No physical Spotlight/clicker or physical laptop key-isolation test this run.
  Hotkey callbacks via OBS WebSocket are not equivalent to hardware isolation.
- The 15-file corpus has no extracted embedded media. Embedded audio/video,
  sound routing and arbitrary animation fidelity need dedicated media fixtures.
- No pristine-machine download/quarantine/notarization test, denied-permission
  matrix, sleep/wake cycle, projector/monitor reconnect or external NDI receiver.
- No hours-long soak or universal PowerPoint-version/font/corrupt-file coverage.
- The post-suite OBS sample showed 243 skipped render frames out of 9,089 total
  since startup, including loading/stress. A later sample showed 246/15,799,
  60 FPS and about 10% CPU. This is not a zero-dropped-frame guarantee or a leak
  test; startup totals must not be presented as steady-state performance.

## Local Evidence

- `/tmp/pptbridge-qa-phase2-20260907`: initial native/live/PDF results and screenshots.
- `/tmp/pptbridge-qa-cachefix-20260907`: post-fix native results, final OBS JSON log and screenshots.
- `full-obs.log` in that directory is the passing cache-only functional run;
  `full-obs-crop.log` is the failed, discarded startup-framing experiment.
- New regression: `native-plugin/tests/cache_replacement_smoke.mm`.
- Final installed executable SHA-256: `296f4fdb68252041edfac083c130206af78792ceb59dda45e5aaf364a718fce2`.
- Pre-cache-fix local bundle backup: `/tmp/pptbridge-before-cache-fix-20260907.plugin`.

After removing the experiment, the retained cache-only source was rebuilt and
installed again. Signature verification and scene/output readback passed; the
full suite was not repeated for this final relink. OBS is running normally with
Program Scene 6, Preview Scene 5, no QA scenes and both original NDI outputs active.

Fixture content, screenshots containing presentation data, credentials and full
OBS logs are deliberately not committed or uploaded.
