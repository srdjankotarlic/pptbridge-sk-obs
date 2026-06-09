# PPTBridge SK for OBS — Case Study

# Problem

PowerPoint was never designed to live inside a broadcast. In real productions — conferences, church streams, webinars, stage events — the same problems come back every show:

- The slideshow takes over a full screen, so operators fall back on fragile window captures that break when a window moves or resizes.
- Presenter notes and the next-slide preview live on the wrong machine or the wrong screen, not on the stage confidence monitor.
- Keyboard focus is a minefield: typing in a browser or chat can advance the deck mid-show.
- Embedded media audio is hard to route cleanly into the program mix.
- Shows with several decks need several fragile capture setups, and switching between them risks controlling the wrong presentation.

# What it does

PPTBridge SK is a native OBS plugin (C++ / Objective-C++) that adds two purpose-built sources:

- **PPTBridge SK Slide** — the clean audience output: program scene, projector, stream, recording.
- **PPTBridge SK Presenter** — the confidence view rendered by the plugin itself inside OBS: current slide, next slide, timer, and notes, with layouts sized for real stage monitors.

Under the hood:

- **Live PowerPoint mode** drives the real slideshow through AppleScript on a serial FIFO queue, fully asynchronous — slide commands never block the OBS UI thread, and every external call has a bounded timeout with terminate/kill fallback.
- **PDF decks** render natively through PDFKit with no PowerPoint installed; PPTX decks convert once and are served from an mtime-validated cache, so a repeated load costs 0 ms instead of a reconversion.
- **Control routing** follows the OBS Program scene: hotkeys, source buttons, Bitfocus Companion, local OSC (`127.0.0.1:57130`), and Spotlight/Clicker Capture all land on the deck that is actually live, so multi-deck shows stay safe.
- Focus-gated hotkeys mean typing in another app never moves a slide; the global clicker capture is an explicit opt-in for stage remotes.

# Real-world use

The plugin is built around shows the author runs personally. A typical event: one OBS scene per speaker deck, a Slide source feeding the projector and stream, a Presenter source on the stage confidence monitor, and slide control from a Companion surface or the speaker's own clicker. Decks stay open side by side and the Program scene decides which one the controls drive.

It is developed and runtime-tested on Apple Silicon (M1 Pro, OBS Studio 32.x) against real production decks, including multi-deck scene collections and mixed PPTX/PDF programs.

# Outcome

- **v0.4.7** is the current stable Apple Silicon release, with an Intel Mac beta and a Windows beta installer published alongside it.
- The live command pipeline survived an external code audit: synchronous UI-thread calls, pipe-drain deadlocks, and unbounded process timeouts were found and fixed, and `tests/audit_guardrails.py` now locks those fixes in so regressions fail fast.
- Runtime verification on a real OBS install covers plugin load, multi-deck loading, cache hits, OSC control of every documented path, and clean logs with zero plugin errors.
- The result is a deck workflow that behaves like any other OBS source: add it to a scene, pick a file, and the show runs — no window-capture hacks, no focus accidents, no PowerPoint takeover.
