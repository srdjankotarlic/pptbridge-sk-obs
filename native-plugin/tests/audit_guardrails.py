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
    if "pipes_drained" not in run_task:
        raise AssertionError("RunTask must not read pipe output unless the drain workers finished")
    if "kStopTaskTimeoutSeconds" not in source:
        raise AssertionError("PowerPoint live stop needs its own short timeout, not the default task timeout")

    stop_session = extract_function(source, "bool StopPowerPointLiveSession(")
    if "kStopTaskTimeoutSeconds" not in stop_session:
        raise AssertionError("PowerPoint live stop must pass the short stop timeout to osascript")
    live_query = extract_function(source, "bool QueryPowerPointLiveState(")
    if "kLiveTaskTimeoutSeconds" not in live_query:
        raise AssertionError("PowerPoint live state sync must use a short live-task timeout")
    live_runner = extract_function(source, "bool RunPowerPointLiveCommand(")
    if "kLiveTaskTimeoutSeconds" not in live_runner:
        raise AssertionError("PowerPoint live commands must use a short live-task timeout")
    pdf_export = extract_function(source, "bool ConvertPptxToPdfWithPowerPoint(")
    if "kPowerPointExportTimeoutSeconds" not in pdf_export:
        raise AssertionError("PowerPoint Save As PDF export must use the export timeout, not the default task timeout")
    if "dispatch_queue_create(\"com.srdjankotarlic.pptbridge.live\", DISPATCH_QUEUE_SERIAL)" not in source:
        raise AssertionError("Live PowerPoint AppleScript operations need one FIFO serial queue")

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
    start_live = extract_function(source, "void PresentationDocument::StartLivePowerPointAsync(")
    if "impl_->live_ready = false" not in start_live:
        raise AssertionError("START/RESTART must clear stale live-ready state before relaunching PowerPoint")
    if "impl_->live_window_title.clear()" not in start_live:
        raise AssertionError("START/RESTART must clear the stale slideshow window title before relaunching")
    stop_async = extract_function(source, "void PresentationDocument::StopLivePowerPointAsync(")
    if "std::thread" in stop_async or "detach(" in stop_async:
        raise AssertionError("Async live stop should use the FIFO live queue, not one detached thread per stop")
    if "dispatch_async(impl_->live_queue" not in stop_async:
        raise AssertionError("Async live stop must dispatch through the FIFO live queue")

    sync_live = extract_function(source, "void PresentationDocument::SyncLiveStateAsync(")
    if "std::thread" in sync_live or "detach(" in sync_live:
        raise AssertionError("Live state sync should use the FIFO live queue, not detached threads")
    if "dispatch_async(impl_->live_queue" not in sync_live:
        raise AssertionError("Live state sync must dispatch through the FIFO live queue")

    live_command = extract_function(source, "void PresentationDocument::RunLivePowerPointCommandAsync(")
    if "std::thread" in live_command or "detach(" in live_command:
        raise AssertionError("Live PowerPoint commands should use the FIFO live queue, not detached threads")
    if "live_command_mutex" in live_command:
        raise AssertionError("The FIFO live queue should serialize live commands instead of a non-FIFO mutex")
    if "dispatch_async(impl_->live_queue" not in live_command:
        raise AssertionError("Live PowerPoint commands must dispatch through the FIFO live queue")
    if "self->impl_->live_ready = false" not in live_command:
        raise AssertionError("Failed live commands must mark the PowerPoint slideshow as not ready")

    sync_live = extract_function(source, "void PresentationDocument::SyncLiveStateAsync(")
    if "self->impl_->live_ready = false" not in sync_live:
        raise AssertionError("Failed live state sync must mark the PowerPoint slideshow as not ready")

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
    presenter_props = extract_function(source_slide, "void add_presenter_customization_properties(")
    for key in (
        "presenter_background_color",
        "presenter_background_image_path",
        "presenter_background_image_opacity_percent",
        "presenter_show_cue_list",
    ):
        if key not in presenter_props:
            raise AssertionError(f"Presenter customization properties must expose {key}")
    if "control_export_cue_list" not in source_slide:
        raise AssertionError("Presenter source should expose a cue-list export button")
    for symbol in (
        "pptbridge_operator_group",
        "pptbridge_operator_next_btn",
        "pptbridge_operator_previous_btn",
        "pptbridge_cue_toggle_current_btn",
        "pptbridge_cue_toggle_next_btn",
        "pptbridge_cue_clear_checks_btn",
        "pptbridge_osc_feedback_enabled",
        "pptbridge_osc_feedback_host",
        "pptbridge_osc_feedback_port",
        "control_send_osc_status",
    ):
        if symbol not in source_slide:
            raise AssertionError(f"Operator/feedback UI must expose {symbol}")

    for label in (
        "Show Control (Operator Mode)",
        "Start / Restart PowerPoint Live Mode",
        "Stop PowerPoint Live Mode",
        "Check / Uncheck Current Cue",
        "Check / Uncheck Next Cue",
        "Send OSC Status Feedback",
        "OSC Status Host/IP",
        "OSC Status Port",
    ):
        if label not in source_slide:
            raise AssertionError(f"macOS operator UI should use clear label: {label}")
    if "START / RESTART - Open PowerPoint Live Mode" in source_slide:
        raise AssertionError("macOS source properties should not use shouty START / RESTART button text")
    if "STOP - Stop PowerPoint Live Mode" in source_slide:
        raise AssertionError("macOS source properties should not use shouty STOP button text")
    operator_props = extract_function(source_slide, "void add_operator_mode_properties(")
    if operator_props.find("pptbridge_operator_start_live_btn") > operator_props.find("pptbridge_operator_status"):
        raise AssertionError("macOS operator UI should show action buttons before the longer status text")
    operator_status_desc = extract_function(source_slide, "std::string describe_operator_status(")
    if "summarize_operator_text(" not in operator_status_desc:
        raise AssertionError("macOS operator status should shorten long cue titles so buttons stay visible")

    header = (ROOT / "src" / "presentation_document.hpp").read_text(encoding="utf-8")
    for symbol in ("background_color", "background_image_path", "show_cue_list"):
        if symbol not in header:
            raise AssertionError(f"PresenterRenderOptions must include {symbol}")
    if "ExportCueList(" not in header:
        raise AssertionError("PresentationDocument must expose a cue-list export API")
    for symbol in (
        "struct CueListItem",
        "struct PresentationStatus",
        "SnapshotStatus(",
        "SetCueChecked(",
        "ToggleCueChecked(",
        "ClearCueChecks(",
    ):
        if symbol not in header:
            raise AssertionError(f"Interactive cue/status support must expose {symbol}")

    presenter_render = extract_function(source, "bool PresentationDocument::RenderPresenterBGRA(")
    for symbol in ("DrawPresenterBackgroundImage", "DrawCueList", "options.background_color"):
        if symbol not in presenter_render:
            raise AssertionError(f"Presenter renderer must use {symbol}")
    if "checked_cues" not in source:
        raise AssertionError("Cue list needs persistent check/uncheck state")

    osc_header = (ROOT / "src" / "pptbridge_osc_server.hpp").read_text(encoding="utf-8")
    osc_source = (ROOT / "src" / "pptbridge_osc_server.cpp").read_text(encoding="utf-8")
    if "SendOscStatusFeedback(" not in osc_header:
        raise AssertionError("OSC/Companion feedback must expose a status sender API")
    for path in (
        "/pptbridge/status/current",
        "/pptbridge/status/total",
        "/pptbridge/status/title",
        "/pptbridge/status/next_title",
        "/pptbridge/status/timer",
        "/pptbridge/status/live",
        "/pptbridge/status/black",
    ):
        if path not in osc_source:
            raise AssertionError(f"OSC/Companion feedback must send {path}")

    plugin_main_mac = (ROOT / "src" / "plugin-main.mm").read_text(encoding="utf-8")
    for label in (
        "PPTBridge SK: Local OSC Control On/Off",
        "PPTBridge SK: Spotlight/Clicker Capture On/Off",
    ):
        if label not in plugin_main_mac:
            raise AssertionError(f"macOS Tools menu should use clear On/Off label: {label}")
    if "PPTBridge SK: Toggle Local OSC Control" in plugin_main_mac:
        raise AssertionError("macOS Tools menu should not use vague Toggle Local OSC Control wording")
    if "PPTBridge SK: Toggle Spotlight/Clicker Capture" in plugin_main_mac:
        raise AssertionError("macOS Tools menu should not use vague Toggle Spotlight/Clicker Capture wording")
    mac_defaults = extract_function(plugin_main_mac, "void apply_default_hotkeys_if_needed()")
    if "{ OBS_KEY_2, OBS_KEY_RIGHT }" not in mac_defaults:
        raise AssertionError("macOS default Next Slide hotkeys must include Right Arrow while OBS is focused")
    if "{ OBS_KEY_1, OBS_KEY_LEFT }" not in mac_defaults:
        raise AssertionError("macOS default Previous Slide hotkeys must include Left Arrow while OBS is focused")

    win_source = (ROOT / "src" / "presentation_document_win.cpp").read_text(encoding="utf-8")
    win_runner = extract_function(win_source, "bool RunProcessCapture(")
    if "WaitForSingleObject(process.hProcess, INFINITE)" in win_runner:
        raise AssertionError("Windows RunProcessCapture needs timeout-backed waiting")
    if "TerminateProcess(" not in win_runner:
        raise AssertionError("Windows RunProcessCapture should terminate timed-out children")
    win_start_live = extract_function(win_source, "void PresentationDocument::StartLivePowerPointAsync(")
    if "impl_->live_ready = false" not in win_start_live:
        raise AssertionError("Windows START/RESTART must clear stale live-ready state before relaunching PowerPoint")

    if "void PresentationDocument::StopLivePowerPointAsync(" not in win_source:
        raise AssertionError("Windows UI controls need async PowerPoint live stop support")

    win_source_slide = (ROOT / "src" / "source_slide_win.cpp").read_text(encoding="utf-8")
    win_stop_control = extract_function(win_source_slide, "bool control_stop_live(")
    if "StopLivePowerPointAsync(" not in win_stop_control:
        raise AssertionError("The Windows stop button must not block the OBS UI thread")
    for symbol in (
        "pptbridge_operator_group",
        "pptbridge_operator_next_btn",
        "pptbridge_operator_previous_btn",
        "pptbridge_cue_toggle_current_btn",
        "pptbridge_cue_toggle_next_btn",
        "pptbridge_cue_clear_checks_btn",
        "pptbridge_osc_feedback_enabled",
        "pptbridge_osc_feedback_host",
        "pptbridge_osc_feedback_port",
        "control_send_osc_status",
    ):
        if symbol not in win_source_slide:
            raise AssertionError(f"Windows operator/feedback UI must expose {symbol}")
    for label in (
        "Show Control (Operator Mode)",
        "Start / Restart PowerPoint Live Mode",
        "Stop PowerPoint Live Mode",
        "Check / Uncheck Current Cue",
        "Check / Uncheck Next Cue",
        "Send OSC Status Feedback",
        "OSC Status Host/IP",
        "OSC Status Port",
    ):
        if label not in win_source_slide:
            raise AssertionError(f"Windows operator UI should use clear label: {label}")
    if "START / RESTART - Open PowerPoint Live Mode" in win_source_slide:
        raise AssertionError("Windows source properties should not use shouty START / RESTART button text")
    if "STOP - Stop PowerPoint Live Mode" in win_source_slide:
        raise AssertionError("Windows source properties should not use shouty STOP button text")
    win_operator_props = extract_function(win_source_slide, "void add_operator_mode_properties(")
    if win_operator_props.find("pptbridge_operator_start_live_btn") > win_operator_props.find("pptbridge_operator_status"):
        raise AssertionError("Windows operator UI should show action buttons before the longer status text")
    win_operator_status_desc = extract_function(win_source_slide, "std::string describe_operator_status(")
    if "summarize_operator_text(" not in win_operator_status_desc:
        raise AssertionError("Windows operator status should shorten long cue titles so buttons stay visible")
    win_presenter_props = extract_function(win_source_slide, "void add_presenter_customization_properties(")
    for key in (
        "presenter_background_color",
        "presenter_background_image_path",
        "presenter_background_image_opacity_percent",
        "presenter_show_cue_list",
    ):
        if key not in win_presenter_props:
            raise AssertionError(f"Windows presenter customization properties must expose {key}")
    if "control_export_cue_list" not in win_source_slide:
        raise AssertionError("Windows presenter source should expose a cue-list export button")

    win_slide_render = extract_function(win_source, "bool PresentationDocument::RenderSlideBGRA(")
    if "options.background_color" in win_slide_render:
        raise AssertionError("Windows slide renderer must not reference presenter-only render options")
    win_presenter_render = extract_function(win_source, "bool PresentationDocument::RenderPresenterBGRA(")
    for symbol in ("DrawPresenterBackgroundImage", "DrawCueList", "options.background_color"):
        if symbol not in win_presenter_render:
            raise AssertionError(f"Windows presenter renderer must use {symbol}")
    if "bool PresentationDocument::ExportCueList(" not in win_source:
        raise AssertionError("Windows PresentationDocument must implement cue-list export")

    plugin_main_win = (ROOT / "src" / "plugin-main.cpp").read_text(encoding="utf-8")
    win_defaults = extract_function(plugin_main_win, "void apply_default_hotkeys_if_needed()")
    if "{ OBS_KEY_2, OBS_KEY_RIGHT }" not in win_defaults:
        raise AssertionError("Windows default Next Slide hotkeys must include Right Arrow while OBS is focused")
    if "{ OBS_KEY_1, OBS_KEY_LEFT }" not in win_defaults:
        raise AssertionError("Windows default Previous Slide hotkeys must include Left Arrow while OBS is focused")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"audit_guardrails: {exc}", file=sys.stderr)
        raise SystemExit(1)
