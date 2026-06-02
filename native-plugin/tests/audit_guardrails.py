#!/usr/bin/env python3
"""Guardrails for concurrency bugs found in external review.

These are intentionally narrow source checks for patterns that are hard to
exercise in CI without launching OBS and PowerPoint.
"""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
MAC_SOURCE = ROOT / "src" / "presentation_document.mm"


def extract_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"Missing function signature: {signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise AssertionError(f"Missing function body: {signature}")

    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"Unterminated function body: {signature}")


def main() -> int:
    source = MAC_SOURCE.read_text(encoding="utf-8")

    run_task = extract_function(source, "bool RunTask(")
    if "waitUntilExit" in run_task:
        raise AssertionError("RunTask must not wait before draining stdout/stderr pipes")
    if "dispatch_semaphore_wait" not in run_task:
        raise AssertionError("RunTask needs a timeout-backed wait")

    for name in ("Next", "Previous", "First", "Last"):
        body = extract_function(source, f"void PresentationDocument::{name}(")
        if "RunPowerPointLiveCommand(" in body:
            raise AssertionError(f"{name} must not run live PowerPoint commands synchronously")
        if "RunLivePowerPointCommandAsync(" not in body:
            raise AssertionError(f"{name} should dispatch live PowerPoint commands to a worker")

    next_body = extract_function(source, "void PresentationDocument::Next(")
    if "currentLiveSlide" not in next_body or "targetSlideCount" not in next_body:
        raise AssertionError("Live Next needs a final-slide guard before asking PowerPoint to advance")
    if "if currentLiveSlide < targetSlideCount then" not in next_body:
        raise AssertionError("Live Next must ignore extra next commands on the final PowerPoint slide")

    if "void PresentationDocument::StopLivePowerPointAsync(" not in source:
        raise AssertionError("UI controls need async PowerPoint live stop support")

    load_worker = extract_function(source, "void PresentationDocument::LoadOnWorker(")
    if "live_started_now" not in load_worker:
        raise AssertionError("Live startup should track whether this worker just opened PowerPoint")
    if "Preloading presenter notes/thumbnails" not in load_worker:
        raise AssertionError("Live slide startup should prewarm presenter assets in the background")
    if "impl_->presenter_assets_wanted = true" not in load_worker:
        raise AssertionError("Live slide startup should request presenter assets before the presenter source waits")

    source_slide = (ROOT / "src" / "source_slide.mm").read_text(encoding="utf-8")
    stop_control = extract_function(source_slide, "bool control_stop_live(")
    if "StopLivePowerPointAsync(" not in stop_control:
        raise AssertionError("The macOS stop button must not block the OBS UI thread")

    win_source = (ROOT / "src" / "presentation_document_win.cpp").read_text(encoding="utf-8")
    win_runner = extract_function(win_source, "bool RunProcessCapture(")
    if "WaitForSingleObject(process.hProcess, INFINITE)" in win_runner:
        raise AssertionError("Windows RunProcessCapture needs timeout-backed waiting")
    if "TerminateProcess(" not in win_runner:
        raise AssertionError("Windows RunProcessCapture should terminate timed-out children")

    if "void PresentationDocument::StopLivePowerPointAsync(" not in win_source:
        raise AssertionError("Windows UI controls need async PowerPoint live stop support")

    win_source_slide = (ROOT / "src" / "source_slide_win.cpp").read_text(encoding="utf-8")
    win_stop_control = extract_function(win_source_slide, "bool control_stop_live(")
    if "StopLivePowerPointAsync(" not in win_stop_control:
        raise AssertionError("The Windows stop button must not block the OBS UI thread")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"audit_guardrails: {exc}", file=sys.stderr)
        raise SystemExit(1)
