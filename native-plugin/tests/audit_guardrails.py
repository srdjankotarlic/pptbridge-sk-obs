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
    if "kLiveStartTaskTimeoutSeconds" not in source:
        raise AssertionError("PowerPoint live start needs its own timeout so Start Live cannot hang indefinitely")
    if "kLiveStartTaskTimeoutSeconds = 120.0" not in source:
        raise AssertionError("Cold PowerPoint live start must allow Microsoft 365 initialization to finish")
    applescript_file_runner = extract_function(source, "bool RunAppleScriptFile(")
    if "set pptbridge_script_file to POSIX file " not in applescript_file_runner:
        raise AssertionError("AppleScript files must run through an -e wrapper so PowerPoint terminology resolves reliably")
    if "run script pptbridge_script_file with parameters pptbridge_script_args" not in applescript_file_runner:
        raise AssertionError("AppleScript files must use variable-backed parameters to avoid wrapper parse failures")
    if "[arguments addObject:ToNSString(script_path.string())]" in applescript_file_runner:
        raise AssertionError("AppleScript files must not be passed directly as osascript's first argument")
    if "AppleScriptListLiteral(script_arguments)" not in applescript_file_runner:
        raise AssertionError("AppleScript file arguments must be passed through a quoted AppleScript parameter list")
    terminology_wrapper = extract_function(source, "std::string PowerPointTerminologyWrapped(")
    if 'using terms from application \\"Microsoft PowerPoint\\"' not in terminology_wrapper:
        raise AssertionError("PowerPoint AppleScript files must compile with the PowerPoint terminology dictionary")

    stop_session = extract_function(source, "bool StopPowerPointLiveSession(")
    if "kStopTaskTimeoutSeconds" not in stop_session:
        raise AssertionError("PowerPoint live stop must pass the short stop timeout to osascript")
    live_query = extract_function(source, "bool QueryPowerPointLiveState(")
    if "kLiveTaskTimeoutSeconds" not in live_query:
        raise AssertionError("PowerPoint live state sync must use a short live-task timeout")
    live_runner = extract_function(source, "bool RunPowerPointLiveCommand(")
    if "kLiveTaskTimeoutSeconds" not in live_runner:
        raise AssertionError("PowerPoint live commands must use a short live-task timeout")
    live_start_session = extract_function(source, "bool StartPowerPointLiveSession(")
    if "kLiveStartTaskTimeoutSeconds" not in live_start_session:
        raise AssertionError("PowerPoint live start must use the live-start timeout, not the export timeout")
    if "PowerPointLiveWorkDirectory(pptx_path)" not in live_start_session:
        raise AssertionError("PowerPoint live staging should use a PowerPoint-readable temp folder, not Application Support")
    if "RestartPowerPointIfIdleForLiveRetry(!powerpoint_was_running_before_start)" not in live_start_session:
        raise AssertionError("PowerPoint live start should retry once after safely restarting an idle stuck PowerPoint")
    if "Retry after idle PowerPoint restart also failed" not in live_start_session:
        raise AssertionError("PowerPoint live start retry failures should preserve both attempts in the error")
    if "PowerPointAppleScriptLiveStartSource(powerpoint_bundle)" not in live_start_session:
        raise AssertionError("PowerPoint live start must target the validated PowerPoint application")
    if '@"/usr/bin/open"' not in live_start_session or '@"-b", ToNSString(kPowerPointBundleIdentifier)' not in live_start_session:
        raise AssertionError("PowerPoint live start must open decks through LaunchServices to avoid file-access dialogs")
    if "PreparePowerPointWindowForCaptureAndRestoreFocus()" not in live_start_session:
        raise AssertionError("PowerPoint live start must prepare the slideshow window for ScreenCaptureKit")
    if "auto staged_input = copied_input;" not in live_start_session:
        raise AssertionError("PowerPoint live fallback must track the staged path that was actually created")
    if "staged_input = alternate_copied_input;" not in live_start_session:
        raise AssertionError("PowerPoint live fallback must retain an alternate staged-copy path")
    if 'start_with_retry(staged_input.string(), "staged deck copy", staged_error)' not in live_start_session:
        raise AssertionError("PowerPoint live fallback must launch the staged path that was actually created")
    if 'start_with_retry(copied_input.string(), "staged deck copy", staged_error)' in live_start_session:
        raise AssertionError("PowerPoint live fallback must not always launch the primary staged path")
    start_once = live_start_session[
        live_start_session.find("auto start_once") : live_start_session.find("auto start_with_retry")
    ]
    if start_once.find("PreparePowerPointWindowForCaptureAndRestoreFocus()") < start_once.find(
        "ParseLivePowerPointOutput(std_out, snapshot, attempt_error)"
    ):
        raise AssertionError("PowerPoint must only be activated after the exact requested slideshow is running")
    pdf_export = extract_function(source, "bool ConvertPptxToPdfWithPowerPoint(")
    if "kPowerPointExportTimeoutSeconds" not in pdf_export:
        raise AssertionError("PowerPoint Save As PDF export must use the export timeout, not the default task timeout")
    if "PowerPointAppleScriptSaveAsSource(powerpoint_bundle)" not in pdf_export:
        raise AssertionError("PowerPoint Save As PDF export must target the validated PowerPoint application")
    if "std::string PowerPointAppleScriptSaveAsSource()" in source:
        raise AssertionError("PowerPoint Save As PDF AppleScript source must receive the app bundle path")
    save_as_source = extract_function(source, "std::string PowerPointAppleScriptSaveAsSource(")
    if "kPowerPointAppleEventTimeoutSeconds" not in source:
        raise AssertionError("PowerPoint Save As PDF fallback needs an AppleEvent timeout constant")
    if "std::to_string(kPowerPointAppleEventTimeoutSeconds)" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must pass the AppleEvent timeout into AppleScript")
    if "with timeout of " not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must wrap PowerPoint AppleEvents in an AppleScript timeout")
    if "((POSIX file candidate) as alias)" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must normalize POSIX input paths before active deck matching")
    if "set raw_input_path to item 1 of argv" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must preserve and normalize the raw input path")
    if "wait_for_active_presentation(input_path, 20)" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must verify the staged deck became active before export")
    if "if my active_presentation_path() is expected_path then" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must match the active deck path before exporting")
    if "save opened_presentation in (POSIX file output_path) as save as PDF" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must export the verified deck")
    if "save active presentation" in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must not export an unrelated active deck")
    if "PowerPointTerminologyWrapped(source)" not in save_as_source:
        raise AssertionError("PowerPoint Save As PDF fallback must wrap generated AppleScript with PowerPoint terms")
    app_tell = extract_function(source, "std::string PowerPointApplicationTellLine(")
    if "FindPowerPointBundle()" not in app_tell or 'tell application \\"Microsoft PowerPoint\\"' not in app_tell:
        raise AssertionError("PowerPoint AppleScript helpers must validate the app bundle before using the display-name target")
    if '"tell application " + AppleScriptStringLiteral(bundle)' in app_tell:
        raise AssertionError("PowerPoint AppleScript helpers must not emit a POSIX .app path as the tell target")
    live_handlers = extract_function(source, "std::string PowerPointAppleScriptLiveHandlers(")
    if "PowerPointApplicationTellLine(powerpoint_bundle)" not in live_handlers:
        raise AssertionError("PowerPoint live handlers must use the validated application target, not only the app name")
    if "snapshot_for_path" not in live_handlers:
        raise AssertionError("PowerPoint live handlers must snapshot by deck path")
    for removed_handler in (
        "find_presentation_by_path",
        "snapshot_for_presentation",
        "presentation_posix_path",
    ):
        if removed_handler in live_handlers:
            raise AssertionError("PowerPoint live AppleScript must not pass presentation objects between handlers")
    for signature in (
        "std::string PowerPointAppleScriptLiveStartSource(",
        "std::string PowerPointAppleScriptLiveQuerySource(",
        "std::string PowerPointAppleScriptLiveStopSource(",
        "std::string PowerPointAppleScriptLiveCommandSource(",
    ):
        live_source = extract_function(source, signature)
        if "PowerPointTerminologyWrapped(source)" not in live_source:
            raise AssertionError(f"{signature} must wrap generated AppleScript with PowerPoint terms")
    live_start_source = extract_function(source, "std::string PowerPointAppleScriptLiveStartSource(")
    if "on start_slide_show_for_path(target_path)" not in live_start_source:
        raise AssertionError("PowerPoint live start must locate the requested deck by exact path")
    if "if candidatePath is target_path then" not in live_start_source:
        raise AssertionError("PowerPoint live start must compare each open deck to the requested path")
    if "start_slide_show_for_path(input_path)" not in live_start_source:
        raise AssertionError("PowerPoint live start must start the exact requested deck")
    if "set targetPresentation to active presentation" in live_start_source:
        raise AssertionError("PowerPoint live start must not route a second source to whichever deck is active")
    if "open POSIX file input_path" in live_start_source:
        raise AssertionError("PowerPoint live start must not trigger the modal AppleScript file-access path")
    if "std::string PowerPointAppleScriptLiveCommandSource(const std::string &command_line)" in source:
        raise AssertionError("PowerPoint live command AppleScript source must receive the app bundle path")
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
    if "impl_->live_request_generation += 1" not in start_live:
        raise AssertionError("START/RESTART must invalidate results from older live requests")
    stop_async = extract_function(source, "void PresentationDocument::StopLivePowerPointAsync(")
    if "std::thread" in stop_async or "detach(" in stop_async:
        raise AssertionError("Async live stop should use the FIFO live queue, not one detached thread per stop")
    if "dispatch_async(impl_->live_queue" not in stop_async:
        raise AssertionError("Async live stop must dispatch through the FIFO live queue")
    if "request_generation = ++impl_->live_request_generation" not in stop_async:
        raise AssertionError("Async live stop must invalidate an older in-flight start")
    stop_on_queue = extract_function(source, "void PresentationDocument::StopLivePowerPointOnLiveQueue(")
    if "impl_->live_request_generation != request_generation" not in stop_on_queue:
        raise AssertionError("A completed old stop must not overwrite a newer live-start request")

    sync_live = extract_function(source, "void PresentationDocument::SyncLiveStateAsync(")
    if "std::thread" in sync_live or "detach(" in sync_live:
        raise AssertionError("Live state sync should use the FIFO live queue, not detached threads")
    if "dispatch_async(impl_->live_queue" not in sync_live:
        raise AssertionError("Live state sync must dispatch through the FIFO live queue")
    if "self->impl_->live_request_generation != request_generation" not in sync_live:
        raise AssertionError("Live sync must ignore results from an older start/stop generation")

    live_command = extract_function(source, "void PresentationDocument::RunLivePowerPointCommandAsync(")
    if "std::thread" in live_command or "detach(" in live_command:
        raise AssertionError("Live PowerPoint commands should use the FIFO live queue, not detached threads")
    if "live_command_mutex" in live_command:
        raise AssertionError("The FIFO live queue should serialize live commands instead of a non-FIFO mutex")
    if "dispatch_async(impl_->live_queue" not in live_command:
        raise AssertionError("Live PowerPoint commands must dispatch through the FIFO live queue")
    if "self->impl_->live_ready = false" not in live_command:
        raise AssertionError("Failed live commands must mark the PowerPoint slideshow as not ready")
    if "self->impl_->live_request_generation != request_generation" not in live_command:
        raise AssertionError("Live commands must ignore results from an older start/stop generation")

    sync_live = extract_function(source, "void PresentationDocument::SyncLiveStateAsync(")
    if "self->impl_->live_ready = false" not in sync_live:
        raise AssertionError("Failed live state sync must mark the PowerPoint slideshow as not ready")

    load_worker = extract_function(source, "void PresentationDocument::LoadOnWorker(")
    if "live_started_now" not in load_worker:
        raise AssertionError("Live startup should track whether this worker just opened PowerPoint")
    if "dispatch_sync(impl_->live_queue" not in load_worker:
        raise AssertionError("Live startup must serialize with stop, sync, and navigation operations")
    if "impl_->live_request_generation != live_request_generation" not in load_worker:
        raise AssertionError("Live startup must reject a result from an older user request")
    if "Discarded stale PowerPoint live-start result" not in load_worker:
        raise AssertionError("A stale live-start result must be cleaned up instead of reopening PowerPoint")
    if "if (live_enabled && !presenter_assets_wanted)" in load_worker:
        raise AssertionError("Manual live mode must still prepare the static preview instead of returning blank")
    if "!live_enabled || live_auto_start || live_start_requested || already_live_ready || live_started_now" not in load_worker:
        raise AssertionError("Manual live mode must not auto-open PowerPoint just to build a static preview")
    if "restart_for_queued_request" not in load_worker or "StartLoadIfNeeded(false)" not in load_worker:
        raise AssertionError("A Start Live request made while notes/media are loading must continue after the current load finishes")
    if "Continuing queued load/start request" not in load_worker:
        raise AssertionError("Queued live-start continuation should be visible in OBS logs")
    early_preview = load_worker.find("Opened static preview")
    metadata_extract = load_worker.find("ExtractDeckMetadata")
    if early_preview == -1 or metadata_extract == -1 or early_preview > metadata_extract:
        raise AssertionError("Static preview should become renderable before slow notes/media extraction")

    source_slide = (ROOT / "src" / "source_slide.mm").read_text(encoding="utf-8")
    plugin_main = (ROOT / "src" / "plugin-main.mm").read_text(encoding="utf-8")
    default_hotkeys = extract_function(plugin_main, "void apply_default_hotkeys_if_needed()")
    if 'apply_default_bindings_if_empty(\n    g_next_hotkey,\n    { OBS_KEY_2, OBS_KEY_RIGHT }' in default_hotkeys:
        raise AssertionError("Default Next Slide hotkey must not bind plain Right Arrow")
    if 'apply_default_bindings_if_empty(\n    g_previous_hotkey,\n    { OBS_KEY_1, OBS_KEY_LEFT }' in default_hotkeys:
        raise AssertionError("Default Previous Slide hotkey must not bind plain Left Arrow")
    clicker_defaults = extract_function(plugin_main, "void append_default_clicker_bindings(")
    if "kVK_RightArrow" in clicker_defaults or "kVK_LeftArrow" in clicker_defaults:
        raise AssertionError("Global clicker capture defaults must not swallow plain left/right arrows")
    plain_clicker_filter = extract_function(plugin_main, "bool is_plain_typing_key_for_clicker(")
    for key in ("kVK_LeftArrow", "kVK_RightArrow"):
        if key not in plain_clicker_filter:
            raise AssertionError(f"Global clicker capture should leave {key} available to the operator")

    stop_control = extract_function(source_slide, "bool control_stop_live(")
    if "StopLivePowerPointAsync(" not in stop_control:
        raise AssertionError("The macOS stop button must not block the OBS UI thread")
    start_control = extract_function(source_slide, "bool control_start_live(")
    if "!selected_deck_is_pptx(context)" not in start_control:
        raise AssertionError("PowerPoint live start must ignore non-PPTX/PDF decks instead of doing nothing silently")
    if "PowerPoint Live Mode is only available for .pptx decks" not in start_control:
        raise AssertionError("PDF/non-PPTX live start should leave a clear user-facing explanation")
    if "enable_live_mode_for_matching_slide_sources(context)" not in start_control:
        raise AssertionError("Start / Restart must enable live capture on matching Slide sources")
    enable_matching_live = extract_function(
        source_slide, "void enable_live_mode_for_matching_slide_sources("
    )
    matching_slide_dispatch = extract_function(
        source_slide, "void for_each_matching_slide_source("
    )
    if "SourceTokens(" not in matching_slide_dispatch:
        raise AssertionError("Live start must locate every matching Slide source")
    if 'obs_data_set_bool(settings, "use_live_powerpoint", true)' not in enable_matching_live:
        raise AssertionError("Live start must persist True Live PowerPoint Mode on matching Slide sources")
    if "obs_source_update(slide_context->source, settings)" not in enable_matching_live:
        raise AssertionError("Live start must immediately apply the updated Slide source settings")
    if "reset_live_child_sources(context, false)" not in start_control:
        raise AssertionError("Start / Restart must discard a stale macOS capture source before relaunching")
    reset_live_children = extract_function(source_slide, "void reset_live_child_sources(")
    for symbol in (
        "release_live_capture_source(context)",
        "clear_live_audio_source(context)",
        "live_capture_suppressed_after_stop = suppress_auto_recovery",
    ):
        if symbol not in reset_live_children:
            raise AssertionError(f"Live child reset must include {symbol}")
    if "stop_live_mode_for_matching_slide_sources(context)" not in stop_control:
        raise AssertionError("Stop from Presenter properties must suppress auto-recovery on matching Slide sources")
    reattach_control = extract_function(source_slide, "bool control_reattach_live(")
    if "reattach_live_mode_for_matching_slide_sources(context)" not in reattach_control:
        raise AssertionError("Manual reattach from Presenter properties must reset matching Slide sources")
    if "reset_live_child_sources(context, false)" not in reattach_control:
        raise AssertionError("Manual reattach must recreate the macOS capture source, not reuse a stale stream")
    if "return true;" not in reattach_control:
        raise AssertionError("Manual reattach should refresh source properties immediately")
    source_update = extract_function(source_slide, "void source_update(")
    if "CountSources(context->pptx_path, RegisteredSourceKind::Slide) <= 1" not in source_update:
        raise AssertionError("Changing one duplicated Slide source must not stop another source's live session")
    texture_destroy_block = source_update[source_update.find("if (size_changed)") :]
    if not texture_destroy_block.startswith("if (size_changed)"):
        raise AssertionError("Only source dimension changes should destroy the OBS texture during source_update")
    if "presenter_options_changed" in texture_destroy_block.split("context->rendered_state_version", 1)[0]:
        raise AssertionError("Presenter property edits must refresh pixels without destroying the active OBS texture")
    find_live_window = extract_function(source_slide, "CGWindowID find_powerpoint_window_id(")
    if "kCGWindowListOptionAll" not in find_live_window:
        raise AssertionError("macOS live capture must find slideshow windows outside the current Space")
    source_tick = extract_function(source_slide, "void source_tick(")
    for required in (
        "live_capture_is_renderable(context)",
        "live_capture_missing_since",
        "release_live_capture_source(context)",
        "live_watchdog_ready",
        "StartLivePowerPointAsync()",
        "Live slideshow session closed unexpectedly; restarting PowerPoint live mode",
    ):
        if required not in source_tick:
            raise AssertionError(f"macOS live watchdog must recover zero-frame capture streams via {required}")
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
    if "selected_deck_is_pdf(context)" not in operator_props:
        raise AssertionError("Operator UI must detect PDF decks")
    if "should_show_powerpoint_live_controls(context)" not in operator_props:
        raise AssertionError("Operator UI must gate PowerPoint live buttons by selected deck type")
    if "PDF decks do not need PowerPoint Live Mode" not in operator_props:
        raise AssertionError("Operator UI should explain that PDF decks are controlled directly")
    if operator_props.find("pptbridge_operator_start_live_btn") > operator_props.find("pptbridge_operator_status"):
        raise AssertionError("macOS operator UI should show action buttons before the longer status text")
    operator_status_desc = extract_function(source_slide, "std::string describe_operator_status(")
    if "summarize_operator_text(" not in operator_status_desc:
        raise AssertionError("macOS operator status should shorten long cue titles so buttons stay visible")
    if "PowerPoint live mode not needed" not in operator_status_desc:
        raise AssertionError("Operator status should make PDF live-mode behavior clear")
    source_properties = extract_function(source_slide, "obs_properties_t *source_properties(")
    if "pptbridge_pdf_live_note" not in source_properties:
        raise AssertionError("PDF source properties should show a clear note instead of live-mode controls")
    if "PowerPoint Live Mode, PowerPoint resize controls, and PowerPoint app-audio routing are only shown for .pptx files" not in source_properties:
        raise AssertionError("PDF source properties should explain why live controls are hidden")
    if "powerpoint_live_available && obs_data_get_bool(settings, \"use_live_powerpoint\")" not in source_slide:
        raise AssertionError("source_update should normalize stored live-mode settings off for PDF decks")

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
    if "live_waiting_for_manual_start" not in presenter_render:
        raise AssertionError("Presenter renderer should explain manual PowerPoint live mode before showing conversion errors")
    if "PowerPoint live mode is manual. Click Start / Restart PowerPoint Live Mode" not in presenter_render:
        raise AssertionError("Presenter manual-live message should point users to Start / Restart")
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
        "/pptbridge/status/deck_name",
        "/pptbridge/status/deck_path",
        "/pptbridge/status/source_name",
        "/pptbridge/status/loading",
        "/pptbridge/status/loaded",
        "/pptbridge/status/error",
        "/pptbridge/status/cue_current_checked",
        "/pptbridge/status/cue_next_checked",
        "/pptbridge/status/cue_checked_count",
    ):
        if path not in osc_source:
            raise AssertionError(f"OSC/Companion feedback must send {path}")
    companion_template = ROOT / "companion" / "PPTBridge-SK-Companion-OSC-Template.json"
    if not companion_template.exists():
        raise AssertionError("Companion OSC starter template must be included")
    companion_template_text = companion_template.read_text(encoding="utf-8")
    for symbol in (
        "Generic OSC",
        "/pptbridge/next",
        "/pptbridge/previous",
        "/pptbridge/status/current",
        "/pptbridge/status/deck_name",
        "/pptbridge/status/cue_current_checked",
    ):
        if symbol not in companion_template_text:
            raise AssertionError(f"Companion template should include {symbol}")
    make_release = (ROOT / "scripts" / "make-release.sh").read_text(encoding="utf-8")
    for symbol in (
        "COMPANION-CONTROL.md",
        "PPTBridge-SK-Companion-OSC-Template.json",
        "scripts/send-osc.sh",
        "export TZ=UTC",
        'touch -h -t 202001010000',
    ):
        if symbol not in make_release:
            raise AssertionError(f"macOS release ZIP should include {symbol}")

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
    if 'apply_default_bindings_if_empty(\n    g_next_hotkey,\n    { OBS_KEY_2 }' not in mac_defaults:
        raise AssertionError("macOS default Next Slide hotkey should be 2 only")
    if 'apply_default_bindings_if_empty(\n    g_previous_hotkey,\n    { OBS_KEY_1 }' not in mac_defaults:
        raise AssertionError("macOS default Previous Slide hotkey should be 1 only")

    win_source = (ROOT / "src" / "presentation_document_win.cpp").read_text(encoding="utf-8")
    win_cmake = (ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
    win_pdf_renderer = (ROOT / "src" / "windows_pdf_renderer.cpp").read_text(encoding="utf-8")
    for symbol in (
        "src/windows_pdf_renderer.cpp",
        "windowsapp",
        "PPTBRIDGE_BUILD_WINDOWS_PDF_SMOKE",
    ):
        if symbol not in win_cmake:
            raise AssertionError(f"Windows PDF build integration must include {symbol}")
    for symbol in (
        "PdfDocument::LoadFromFileAsync",
        "RenderToStreamAsync",
        "BitmapEncoder::PngEncoderId",
        "BackgroundColor(winrt::Windows::UI::Colors::White())",
        "WriteBytesAtomically",
    ):
        if symbol not in win_pdf_renderer:
            raise AssertionError(f"Native Windows PDF renderer must use {symbol}")
    win_load_worker = extract_function(win_source, "void PresentationDocument::LoadOnWorker(")
    for symbol in (
        "const bool is_pdf_source = IsPdfExtension(impl_->path)",
        "RenderPdfDeckData(source_path, impl_->cache_root, deck_data, load_error)",
        "Reused cached Windows PDF pages",
        "fresh native PDF render",
    ):
        if symbol not in win_load_worker:
            raise AssertionError(f"Windows document loading must preserve native PDF behavior via {symbol}")
    if "PDF input is not supported on Windows" in win_source:
        raise AssertionError("Windows must not reject valid PDF input after native PDF support ships")
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
    for symbol in (
        "*.potm *.pdf",
        "selected_deck_is_pdf(context)",
        "should_show_powerpoint_live_controls(context)",
        "pptbridge_pdf_mode_note",
        "native Windows PDF render",
        'obs_data_set_bool(settings, "use_live_powerpoint", false)',
        'obs_data_set_bool(settings, "auto_start_live_powerpoint", false)',
        'obs_data_set_bool(settings, "close_live_powerpoint_on_shutdown", false)',
        'obs_data_set_bool(settings, "audio_enabled", false)',
        'obs_data_set_bool(settings, "use_live_app_audio", false)',
    ):
        if symbol not in win_source_slide:
            raise AssertionError(f"Windows PDF source UI/settings must include {symbol}")
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
    if 'apply_default_bindings_if_empty(\n    g_next_hotkey,\n    { OBS_KEY_2 }' not in win_defaults:
        raise AssertionError("Windows default Next Slide hotkey should be 2 only")
    if 'apply_default_bindings_if_empty(\n    g_previous_hotkey,\n    { OBS_KEY_1 }' not in win_defaults:
        raise AssertionError("Windows default Previous Slide hotkey should be 1 only")

    windows_installer = (ROOT / "windows-package" / "INSTALL.cmd").read_text(encoding="utf-8")
    if 'Start-Process -FilePath "cmd.exe"' in windows_installer:
        raise AssertionError("Windows installer elevation must not use Start-Process, which can fail with duplicate PATH keys")
    for symbol in (
        "$startInfo = [Diagnostics.ProcessStartInfo]::new()",
        "$startInfo.FileName = $env:ComSpec",
        '$startInfo.Arguments = \'/d /s /c ""\'',
        '$startInfo.Verb = "runas"',
        "$startInfo.UseShellExecute = $true",
        "$adminProcess.WaitForExit()",
        "Administrator permission was cancelled",
    ):
        if symbol not in windows_installer:
            raise AssertionError(f"Windows installer elevation must include {symbol}")
    if windows_installer.count('if not "%PPTBRIDGE_INSTALLER_NO_PAUSE%"=="1" pause') != 2:
        raise AssertionError("Windows installer automation must skip both success and failure pauses")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"audit_guardrails: {exc}", file=sys.stderr)
        raise SystemExit(1)
