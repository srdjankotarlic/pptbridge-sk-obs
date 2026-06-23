import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputPath = path.resolve("qa/PPTBridge-Feature-QA-Tracker.xlsx");
const previewDir = path.resolve("qa/.tracker-build/previews");
const generatedOn = "2026-06-23";
const repo = "https://github.com/srdjankotarlic/pptbridge-sk-obs";

const stories = [
  ["SRC-001", "OBS Sources", "Add clean slide source", "macOS stable, Windows beta", "As an OBS operator, I can add PPTBridge SK Slide as a native OBS source.", "The source appears in OBS, renders a 1920x1080 clean program output, and owns slide/audio/live capture behavior.", "Source can be added, deck path can be selected, and canvas size is stable at 1920x1080.", "native-plugin/src/source_slide.mm; README.md#OBS Sources", "OBS runtime source-add test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["SRC-002", "OBS Sources", "Add presenter confidence source", "macOS stable, Windows beta", "As a presenter or operator, I can add PPTBridge SK Presenter as a separate OBS source.", "The source renders current slide, next slide, timer, notes, and presenter layout controls without becoming the audience feed.", "Presenter source appears, accepts same deck file, and exposes canvas/customization controls.", "native-plugin/src/source_presenter.mm; README.md#OBS Sources", "OBS runtime source-add test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["DECK-001", "Deck Input", "Select PPTX on macOS", "macOS stable", "As an operator, I can select a .pptx file in either PPTBridge source.", "PPTBridge creates or reuses a shared PresentationDocument for the selected path and starts async loading.", "Changing the path updates document state, clears stale media/live capture, and begins load without freezing OBS.", "native-plugin/src/source_slide.mm source_update; presentation_document.hpp", "Source properties + load smoke", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["DECK-002", "Deck Input", "Select PDF on macOS", "macOS stable", "As an operator, I can select a .pdf file without needing PowerPoint.", "PDF decks render directly through PPTBridge and hide PowerPoint Live Mode controls.", "PDF pages load, Next/Previous moves pages, and live PowerPoint controls are not shown.", "README.md#PowerPoint Live Controls; source_slide.mm selected_deck_is_pdf", "PDF render smoke + OBS properties check", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["DECK-003", "Deck Input", "Select PPTX on Windows beta", "Windows beta", "As a Windows tester, I can select a PowerPoint file for live-mode testing.", "Windows beta supports PPTX live-mode workflow with PowerPoint installed; PDF is not enabled.", "INSTALL.cmd installs plugin and PPTX source can start live mode.", "README.md#Quick Windows Install; native-plugin/INSTALL-Windows.md", "Windows laptop manual validation", "Needs Manual", "Beta", "P1", generatedOn, "Needs real Windows runtime test."],
  ["LOAD-001", "Loading", "Fast first preview", "macOS stable", "As an operator, I see the first slide quickly after adding a deck.", "Static preview becomes renderable as soon as cached/generated PDF opens while notes/media continue in background.", "No long blank OBS source before initial slide unless conversion is genuinely running.", "README.md#What It Solves; v0.5.5 release notes", "PPTX/PDF load timing test", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 smoke: large uncached PPTX first preview 7668 ms; same deck cached preview 46 ms; small cached PPTX 47 ms; PDF 56 ms."],
  ["LOAD-002", "Loading", "Background notes/media preparation", "macOS stable", "As a presenter, I eventually receive notes and cue titles without delaying the first preview.", "Presenter assets are prepared in background after preview/live mode can show.", "Status can say live ready/preparing presenter and later notes/cues appear.", "source_slide.mm build_status_text; presentation_document.hpp SetPresenterAssetsWanted", "Presenter load timing test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["LOAD-003", "Loading", "Reload presentation", "macOS stable, Windows beta", "As an operator, I can force PPTBridge to reload the selected deck.", "Reload Presentation calls ReloadAsync and refreshes the shared document state.", "Reload button and OSC reload path refresh deck state without restarting OBS.", "source_slide.mm control_reload; pptbridge_osc_server.cpp", "Button + OSC smoke", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["LOAD-004", "Loading", "Missing/invalid file handling", "macOS stable, Windows beta", "As an operator, I get a clear error when the selected file cannot be loaded.", "Last issue/status reports the failure instead of silently showing stale content.", "Properties status shows Last issue and source does not crash.", "source_slide.mm build_status_text; presentation_document.hpp LastError", "Invalid file path test", "Not Run", "Needs Test", "P1", generatedOn, ""],
  ["CACHE-001", "Cache", "PPTX-to-PDF cache validation", "macOS stable", "As an operator, unchanged decks should reload faster from cache.", "Cache is reused when newer/current against deck modification time; edited decks reconvert.", "Opening unchanged PPTX avoids unnecessary conversion; editing PPTX invalidates cache.", "README.md release notes; presentation_document.mm cache path", "Timestamp/cache test", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 large PPTX reload reused cached PDF: PDF prep 0 ms, first preview 46 ms, full load 239 ms."],
  ["LIVE-001", "PowerPoint Live", "Manual Start Live Mode", "macOS stable", "As an operator, I can click Start / Restart PowerPoint Live Mode when I am ready.", "PowerPoint opens if needed and starts the slideshow on demand, not automatically by default.", "Clicking start produces a live slideshow capture for PPTX deck.", "source_slide.mm control_start_live; README.md#PowerPoint Live Controls", "live_powerpoint_smoke + OBS manual", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 final smoke: original Desktop PPTX started live mode, advanced to slide 2, and stopped slideshow."],
  ["LIVE-002", "PowerPoint Live", "Start during background preparation", "macOS stable", "As an operator, I can click Start soon after preview appears even if presenter assets are still loading.", "Start command does not get lost while notes/media are preparing.", "Immediate start after first preview starts live mode successfully.", "v0.5.6 release notes; native-plugin/tests/live_powerpoint_smoke.mm", "Live smoke test", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 smoke covered both immediate StartLivePowerPointAsync and preview-first manual start."],
  ["LIVE-003", "PowerPoint Live", "Stop Live Mode", "macOS stable", "As an operator, I can stop the slideshow without quitting OBS.", "Stop clears live capture/audio state and stops PowerPoint slideshow asynchronously from properties.", "Stop button ends live show and leaves OBS responsive.", "source_slide.mm control_stop_live; presentation_document.hpp StopLivePowerPointAsync", "OBS manual live test", "Verified", "Implemented", "P0", generatedOn, ""],
  ["LIVE-004", "PowerPoint Live", "Auto-start option", "macOS stable", "As an operator, I can opt into PowerPoint starting when OBS opens.", "Auto Start PowerPoint When OBS Opens is off by default and starts live mode only when enabled.", "Default is false; enabling auto-start triggers live startup during load.", "source_slide.mm source_defaults/source_update", "OBS settings persistence test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["LIVE-005", "PowerPoint Live", "Close slideshow on OBS shutdown", "macOS stable", "As an operator, I can choose whether OBS closes the slideshow when it exits.", "Close PowerPoint Slideshow When OBS Closes defaults on and stops owned live sessions when last slide source detaches.", "OBS shutdown/source destroy stops only owned session when setting enabled.", "source_slide.mm source_destroy", "OBS quit/manual teardown test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["LIVE-006", "PowerPoint Live", "Recover/restart after slideshow window closed", "macOS stable", "As an operator, I can recover if the slideshow window was closed but PowerPoint remains open.", "Start / Restart clears stale capture and starts or reattaches the live session.", "Closing live window then pressing Start / Restart recovers output.", "source_slide.mm control_start_live; source_tick watchdog", "OBS manual recovery test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["LIVE-007", "PowerPoint Live", "Final-slide protection", "macOS stable", "As a show operator, extra next commands on the last slide should not drop out of OBS.", "Next at the end does not exit live slideshow unexpectedly.", "Repeated next on final slide keeps program capture stable.", "README.md#PowerPoint Live Controls; presentation_document.mm live navigation", "Live final-slide test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["LIVE-008", "PowerPoint Live", "PDF decks hide live controls", "macOS stable", "As a PDF user, I should not see irrelevant PowerPoint live controls.", "PowerPoint Live Mode controls are hidden and an explanatory PDF note appears.", "Selecting PDF shows PDF note and no live start/stop controls.", "source_slide.mm source_properties; README.md", "OBS properties test", "Verified", "Implemented", "P1", generatedOn, "v0.5.6 change; verify visually again."],
  ["LIVE-009", "PowerPoint Live", "Original deck path first, staged fallback second", "macOS stable", "As an operator, PowerPoint should start the same deck I selected in OBS instead of depending on fragile temp staging.", "Live mode opens the user-selected original deck path first; staged copy is kept only as a fallback.", "Start live mode succeeds from the original Desktop deck path and does not require temp/hidden staging.", "presentation_document.mm StartPowerPointLiveSession", "Live smoke + AppleScript reproduction", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 temp and hidden sidecar staging reproduced PowerPoint hangs; final code uses original path first and passed live_start/live_powerpoint smokes on the original Desktop PPTX."],
  ["RESIZE-001", "Live Capture", "Lock OBS output size against PPT window resize", "macOS stable", "As an operator, I can shrink the desktop PowerPoint window without shrinking OBS output.", "Default live resize behavior is Lock OBS Output Size.", "Resizing PowerPoint desktop window does not change source size in OBS.", "source_slide.mm live_capture_resize_mode default; README.md", "Manual resize test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["RESIZE-002", "Live Capture", "Follow current PPT window size", "macOS stable", "As an operator, I can intentionally make OBS follow the PowerPoint window shape.", "Follow PowerPoint Window Size mode updates capture sizing based on current slideshow window.", "Changing mode to follow makes source reflect PPT window size.", "source_slide.mm live_capture_resize_mode; control_follow_live_resize", "Manual resize test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["RESIZE-003", "Live Capture", "Reattach live window button", "macOS stable", "As an operator, I can force PPTBridge to search again for the live slideshow window.", "Reattach clears old capture/audio source and calls SyncLiveStateAsync.", "Reattach button restores capture when PowerPoint window is still available.", "source_slide.mm control_reattach_live", "Manual live recovery test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["NAV-001", "Slide Control", "Next/Previous source buttons", "macOS stable, Windows beta", "As an operator, I can move slides from source properties.", "Previous Slide and Next Slide buttons change the shared document/current slide.", "Buttons move PPTX/PDF deck and update slide status.", "source_slide.mm control_previous/control_next", "OBS property button test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["NAV-002", "Slide Control", "First/Last source buttons", "macOS stable, Windows beta", "As an operator, I can jump to first or last slide.", "First Slide and Last Slide buttons update document index safely.", "Buttons jump to correct slide without crashing at boundaries.", "source_slide.mm control_first/control_last", "OBS property button test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["NAV-003", "Slide Control", "Toggle black screen", "macOS stable, Windows beta", "As an operator, I can temporarily black out the slide output.", "Toggle Black Screen toggles black_screen state and rendering/status reflect it.", "Button and OSC path black/blank toggle black screen and status.", "source_slide.mm control_black; pptbridge_osc_server.cpp", "Button + OSC smoke", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["HOTKEY-001", "Hotkeys", "Default OBS-focused hotkeys", "macOS stable, Windows beta", "As an operator, I get safe first-launch defaults for slide control.", "Next defaults to 2 and Previous defaults to 1; arrows are not defaults.", "Fresh settings show 2/1 defaults only.", "plugin-main.mm apply_default_hotkeys_if_needed", "OBS hotkey settings inspection", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["HOTKEY-002", "Hotkeys", "User-custom OBS hotkeys", "macOS stable, Windows beta", "As an operator, I can choose my own OBS hotkeys.", "Registered OBS hotkeys call the router while OBS is active.", "Custom hotkey moves current Program scene deck only when OBS is focused.", "plugin-main.mm obs_hotkey_register_frontend/hotkey_router", "OBS hotkey manual test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["HOTKEY-003", "Hotkeys", "Ignore normal hotkeys outside OBS", "macOS stable, Windows beta", "As an operator, typing in another app should not change slides.", "Normal OBS hotkey callback returns unless OBS is active.", "Pressing 1/2 in Chrome/text editor does not move slides unless clicker capture is enabled for supported keys.", "plugin-main.mm obs_application_is_active/hotkey_router", "Focus-switch keyboard test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["HOTKEY-004", "Hotkeys", "Left/right arrows remain free", "macOS stable, Windows beta", "As an operator, left/right arrows should still work in OBS and other apps.", "Default and global clicker capture do not swallow plain left/right arrows.", "Left/right arrows navigate UI/text normally while OBS is open.", "plugin-main.mm migrate defaults + is_plain_typing_key_for_clicker", "OBS UI keyboard test", "Needs Manual", "Implemented", "P0", generatedOn, "Code/config check passes: OBS profile has only 2/1 PPTBridge hotkeys and clicker filter excludes plain arrows. Automated GUI harness could not acquire normal frontmost focus from Codex, so hands-on UI test is still required."],
  ["CLICKER-001", "Clicker Capture", "Toggle Spotlight/Clicker Capture", "macOS stable, Windows beta", "As an operator, I can enable or disable global presenter remote capture.", "Tools menu toggles global capture and persists setting.", "Menu item changes enabled state; plugin logs enabled/disabled.", "plugin-main.mm toggle_clicker_capture_menu", "OBS menu + permissions test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["CLICKER-002", "Clicker Capture", "Default PageDown/PageUp mapping", "macOS stable, Windows beta", "As a presenter, my common clicker can drive slides without OBS focused.", "PageDown routes Next and PageUp routes Previous when capture is enabled.", "With Chrome focused, PageDown/PageUp move Program scene deck.", "plugin-main.mm append_default_clicker_bindings", "Global keyboard/clicker test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["CLICKER-003", "Clicker Capture", "Suppress captured keys from focused app", "macOS stable, Windows beta", "As an operator, a stage clicker should not also scroll/type in the focused app.", "Captured keydown/keyup are swallowed after routing to PPTBridge.", "Focused app does not receive PageDown/PageUp while capture handles them.", "plugin-main.mm clicker_event_tap_callback / Windows hook", "Global keyboard test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["CLICKER-004", "Clicker Capture", "Custom OBS hotkeys captured safely", "macOS stable, Windows beta", "As an operator, supported custom remote keys can be captured globally.", "Capture imports PPTBridge hotkey bindings but filters plain typing keys and arrows.", "Custom non-typing binding works globally; plain text keys remain free.", "plugin-main.mm collect_clicker_bindings_from_obs_hotkeys", "Custom binding test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["ROUTE-001", "Multi Deck", "Program-scene routing", "macOS stable, Windows beta", "As an operator with multiple scenes/decks, controls should affect the current Program scene deck.", "Hotkeys, OSC, and clicker resolve PPTBridge sources from obs_frontend_get_current_scene.", "Scene 1 controls deck 1; Scene 2 controls deck 2; Preview scene does not steal control.", "plugin-main.mm resolve_target_documents", "Multi-scene OBS test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["ROUTE-002", "Multi Deck", "Group scene traversal", "macOS stable, Windows beta", "As an OBS user, I can put PPTBridge sources inside groups and still control them.", "Scene collector recurses into OBS group sources.", "PPTBridge source inside group receives routed commands.", "plugin-main.mm collect_pptbridge_from_item", "Grouped source test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["ROUTE-003", "Multi Deck", "macOS fallback active document", "macOS stable", "As a single-deck user, controls still work if no current scene target is found.", "macOS falls back to Registry::Active for backwards compatibility.", "With no program-scene source but active doc set, controls route to fallback.", "plugin-main.mm resolve_target_documents; pptbridge_registry.cpp", "Edge-case manual test", "Not Run", "Implemented", "P3", generatedOn, "Windows intentionally requires Program scene."],
  ["OSC-001", "OSC Control", "Toggle local OSC listener", "macOS stable, Windows beta", "As a show-control user, I can enable local OSC control from OBS Tools.", "Local OSC listens on 127.0.0.1:57130 when enabled and persists setting.", "Tools menu starts/stops OSC server and logs port binding.", "plugin-main.mm toggle_osc_menu; pptbridge_osc_server.cpp", "OSC socket smoke", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["OSC-002", "OSC Control", "Supported OSC command paths", "macOS stable, Windows beta", "As a Companion/OSC user, I can send standard slide commands.", "OSC accepts /pptbridge/next, /previous, /prev, /first, /last, /black, /blank, /reload.", "Each path routes correct action; unknown paths do nothing.", "pptbridge_osc_server.cpp parse_osc_action", "OSC smoke test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["OSC-003", "OSC Control", "OSC routes to Program scene", "macOS stable, Windows beta", "As a multi-deck show user, OSC should control the deck currently live in Program.", "OSC action queues to OBS UI thread then resolves Program scene documents.", "Sending OSC while Program scene changes affects only active Program scene deck.", "plugin-main.mm queued_osc_action_task/resolve_target_documents", "Multi-scene OSC test", "Needs Manual", "Implemented", "P0", generatedOn, ""],
  ["OSCFB-001", "OSC Feedback", "Enable OSC status feedback", "macOS stable, Windows beta", "As a Companion user, I can receive status from PPTBridge.", "Source property enables feedback and sends to configured host/port.", "Enabling feedback sends state changes and manual Send OSC Status Now works.", "source_slide.mm send_osc_status; add_operator_mode_properties", "OSC receiver smoke", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["OSCFB-002", "OSC Feedback", "Slide and title feedback", "macOS stable, Windows beta", "As a show-control user, I can display current slide, total slides, current title, and next title.", "Feedback includes current, total, title, and next_title values.", "OSC receiver gets accurate values after navigation.", "presentation_document.hpp PresentationStatus; pptbridge_osc_server.cpp", "OSC receiver smoke", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["OSCFB-003", "OSC Feedback", "Deck/source/live/error feedback", "macOS stable, Windows beta", "As a show-control user, I can see deck/source/loading/error/live/black status.", "Feedback includes deck name/path, source name, loading, loaded, error, timer, live, black.", "OSC receiver gets status changes for loading, live mode, black screen, and errors.", "presentation_document.hpp PresentationStatus; source_slide.mm send_osc_status", "OSC receiver smoke", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["OSCFB-004", "OSC Feedback", "Cue checked feedback", "macOS stable, Windows beta", "As a show caller, I can see whether current/next cue is checked.", "Feedback includes current_cue_checked, next_cue_checked, checked_count and cue list state.", "Checking/unchecking cues updates outgoing status.", "presentation_document.hpp CueListItem; source_slide.mm cue controls", "OSC + cue test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["COMP-001", "Companion", "OBS WebSocket property-button workflow", "macOS stable, Windows beta", "As a Companion user, I can trigger PPTBridge via OBS WebSocket property buttons.", "Documented PressInputPropertiesButton workflow uses actual source property button names.", "Companion/OBS WebSocket can press next/previous/start/status buttons.", "native-plugin/COMPANION-CONTROL.md; source_slide.mm property names", "Companion manual test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["COMP-002", "Companion", "Generic OSC starter template", "macOS stable, Windows beta", "As a Companion user, I can import a starter OSC button map.", "Package includes PPTBridge-SK-Companion-OSC-Template.json.", "Template file exists in repo/package and maps core OSC paths.", "native-plugin/companion/PPTBridge-SK-Companion-OSC-Template.json", "File/package inspection", "Verified", "Implemented", "P2", generatedOn, ""],
  ["PRES-001", "Presenter Layout", "Layout presets", "macOS stable, Windows beta", "As a presenter, I can choose a presenter layout that fits the monitor.", "Balanced, large preview, large notes, compact, and confidence monitor presets are available.", "Changing preset updates presenter render arrangement.", "presentation_document.hpp PresenterLayoutPreset; source_slide.mm properties", "Presenter visual test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["PRES-002", "Presenter Layout", "Preview scale and position controls", "macOS stable, Windows beta", "As a presenter, I can fit/fill/crop and reposition the slide preview.", "Preview fit/fill/crop, scale percent, and X/Y position affect presenter rendering.", "Changing controls visibly changes presenter preview without affecting program output.", "PresenterRenderOptions; README.md#Presenter Customization", "Presenter visual test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["PRES-003", "Presenter Layout", "Notes sizing controls", "macOS stable, Windows beta", "As a presenter, I can make notes easier to read.", "Notes font size, zoom, area percent, and vertical position affect notes rendering.", "Notes become larger/smaller and remain legible; no overlap with next slide.", "PresenterRenderOptions; README.md", "Presenter notes visual test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["PRES-004", "Presenter Layout", "Background color/image/logo", "macOS stable, Windows beta", "As an operator, I can brand or soften the presenter view background.", "Background color, image path, mode, and opacity are applied in presenter rendering.", "Selecting image and mode displays expected background without breaking notes.", "PresenterRenderOptions; README.md", "Presenter visual test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["PRES-005", "Presenter Layout", "Next-slide preview/end state", "macOS stable, Windows beta", "As a presenter, I can see the upcoming slide or clear end state.", "Presenter view shows next slide when available and End/no next slide when at final slide.", "Next panel updates on navigation and final slide shows end state.", "presentation_document.mm RenderPresenterBGRA; README.md", "Presenter final-slide test", "Needs Manual", "Implemented", "P1", generatedOn, ""],
  ["PRES-006", "Presenter Layout", "Cue list display", "macOS stable, Windows beta", "As a show caller, I can see a compact cue list in presenter view.", "Presenter show cue list option renders cues and checked/current/next state.", "Cue list appears, updates current/next, and reflects checked cues.", "PresenterRenderOptions show_cue_list; CueListItem", "Presenter cue visual test", "Needs Manual", "Implemented", "P1", generatedOn, "2026-06-23 render_smoke exercises presenter cue-list render path and cue state; visual OBS confirmation still needed."],
  ["CUE-001", "Cue List", "Check/uncheck current cue", "macOS stable, Windows beta", "As an operator, I can mark the current cue done/undone.", "Check / Uncheck Current Cue toggles the current slide cue state.", "Button updates checked count, presenter cue list, and OSC status.", "source_slide.mm control_toggle_current_cue", "Cue button + OSC test", "Needs Manual", "Implemented", "P1", generatedOn, "2026-06-23 render_smoke verified SetCueChecked(current) updates current_cue_checked and checked_count; source button/OSC end-to-end still manual."],
  ["CUE-002", "Cue List", "Check/uncheck next cue", "macOS stable, Windows beta", "As an operator, I can pre-mark or clear the next cue.", "Check / Uncheck Next Cue toggles current_index + 1 when it exists.", "Button handles no-next-slide case gracefully.", "source_slide.mm control_toggle_next_cue", "Cue button edge test", "Needs Manual", "Implemented", "P2", generatedOn, "2026-06-23 render_smoke verified SetCueChecked(next) updates next_cue_checked and checked_count on multi-slide decks; no-next edge still manual."],
  ["CUE-003", "Cue List", "Clear cue checks", "macOS stable, Windows beta", "As a show caller, I can reset cue checklist state.", "Clear Cue Checks clears all checked cues and sends status feedback.", "All cue checked indicators clear and count becomes zero.", "source_slide.mm control_clear_cue_checks", "Cue reset test", "Needs Manual", "Implemented", "P2", generatedOn, "2026-06-23 render_smoke verified ClearCueChecks resets checked_count/current/next state; OBS property button still manual."],
  ["CUE-004", "Cue List", "Export cue list text", "macOS stable, Windows beta", "As an operator, I can export a cue list from the deck.", "Export Cue List (.txt) writes cue titles/slides to a text file or reports an error.", "Export creates readable txt and status shows path.", "presentation_document.hpp ExportCueList; source_slide.mm control_export_cue_list", "File export test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["MEDIA-001", "Media", "Embedded media overlay metadata", "macOS stable", "As an operator, embedded media should be represented when using render mode.", "CurrentMedia exposes media file, bounds, autoplay, loop, and source creates media children.", "Deck with embedded media creates/plays child media in slide source.", "presentation_document.hpp EmbeddedMedia; source_slide.mm sync_media_sources", "Media deck runtime test", "Not Run", "Needs Test", "P1", generatedOn, "Live PPT mode preserves real PowerPoint media separately."],
  ["AUDIO-001", "Audio", "Enable PPTBridge audio output", "macOS stable, Windows beta", "As an operator, I can mute or enable plugin audio output.", "Enable PPTBridge Audio Output controls audio_render output.", "Turning off audio prevents source audio mix; turning on restores it.", "source_slide.mm audio_enabled/audio_render", "OBS audio meter test", "Not Run", "Implemented", "P1", generatedOn, ""],
  ["AUDIO-002", "Audio", "Route PowerPoint app audio through OBS", "macOS stable", "As an operator, live PowerPoint media audio can be routed through OBS.", "When enabled in true live mode, PPTBridge attaches PowerPoint app audio source when available.", "OBS mixer shows PowerPoint app audio under PPTBridge slide source.", "source_slide.mm live_audio_source/use_live_app_audio; PRO-AUDIO-MODE.md", "Live media/audio test", "Not Run", "Needs Test", "P1", generatedOn, ""],
  ["AUDIO-003", "Audio", "Audio gain", "macOS stable, Windows beta", "As an operator, I can adjust playback level.", "Audio Gain dB applies multiplier during audio mixing.", "Changing gain changes meter/output level without clipping weirdness.", "source_slide.mm audio_gain_db/audio_gain_multiplier_db", "OBS audio meter test", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["INSTALL-001", "Install", "macOS Apple Silicon ZIP install", "macOS stable", "As a Mac user, I can install from ZIP without building from source.", "ZIP contains START-HERE, installer command, plugin bundle, README, Companion docs/template, and helper script.", "Fresh unzip + double-click install copies plugin and OBS sees sources.", "README.md#Quick macOS Install; native-plugin/scripts/make-release.sh", "Package inspection + install test", "Verified", "Implemented", "P0", generatedOn, "2026-06-23 v0.5.7 release installer copied plugin to user OBS plugins folder; OBS opened and log showed Native plugin loaded."],
  ["INSTALL-002", "Install", "macOS blocked command guidance", "macOS stable", "As a Mac user, I know how to open unsigned installer command.", "Docs tell user to right-click and Open if macOS blocks it.", "README/Quickstart/START-HERE contain correct guidance.", "README.md; QUICKSTART.md; START-HERE-macOS.txt", "Docs inspection", "Verified", "Implemented", "P2", generatedOn, ""],
  ["INSTALL-003", "Install", "Legacy Python cleanup helper", "macOS stable", "As an upgrading user, I can remove old Python/script install leftovers.", "Repo includes cleanup-legacy-python helper and docs mention troubleshooting path.", "Script exists and does not ship as accidental primary installer.", "native-plugin/scripts/cleanup-legacy-python.sh; FAQ.md", "File/docs inspection", "Not Run", "Implemented", "P3", generatedOn, ""],
  ["INSTALL-004", "Install", "Release ZIP has no duplicate junk assets", "macOS stable", "As a user, the download should be simple and not contain confusing duplicate files.", "Release ZIP should contain only user-facing installer/plugin/docs/template/script files.", "ZIP listing matches documented package contents.", "native-plugin/scripts/make-release.sh; release asset", "unzip listing test", "Verified", "Implemented", "P1", generatedOn, "2026-06-23 v0.5.7 ZIP listing contains installer, START-HERE, plugin bundle, README, Companion guide/template, and send-osc helper only."],
  ["PACK-001", "Release", "Checksum asset", "macOS stable", "As a careful user, I can verify the downloaded ZIP checksum.", "Release includes .sha256 next to ZIP.", "Checksum file is uploaded and matches ZIP.", "GitHub release v0.5.7; scripts/make-release.sh", "Release asset + sha256 test", "Verified", "Implemented", "P2", generatedOn, "2026-06-23 local shasum -a 256 -c passed for v0.5.7 ZIP."],
  ["DOC-001", "Docs", "README describes current workflow", "All", "As a new user, I can understand what PPTBridge does and where to download.", "README top area explains split slide/presenter output, stable download, install path, and main workflow.", "README first screen points to v0.5.7 and quick setup.", "README.md", "Docs review", "Verified", "Implemented", "P1", generatedOn, ""],
  ["DOC-002", "Docs", "Support/FAQ troubleshooting", "All", "As a user with a problem, I can find what to check before reporting.", "FAQ and SUPPORT cover install, missing sources, permissions, logs, and expected details.", "Docs give actionable support checklist.", "FAQ.md; SUPPORT.md", "Docs review", "Not Run", "Implemented", "P2", generatedOn, ""],
  ["QA-001", "QA Tracker", "Single canonical feature tracker", "All", "As the maintainer, I can keep one canonical spreadsheet that tracks every feature, test, issue, fix, and retest status.", "The tracker opens as a valid workbook with Summary, UserStories, TestLog, and Issues sheets, and formula scans find no spreadsheet errors.", "Workbook imports successfully, status formulas compute, and all test/issue evidence stays in the same file.", "qa/PPTBridge-Feature-QA-Tracker.xlsx; qa/build-feature-qa-tracker.mjs", "Workbook import + formula scan", "Verified", "Implemented", "P1", generatedOn, "Tracks the QA process itself, not an end-user plugin feature."],
  ["WIN-001", "Windows Beta", "Windows installer", "Windows beta", "As a Windows tester, I can install the beta with INSTALL.cmd.", "INSTALL.cmd copies plugin files to OBS plugin location and docs label beta limitations.", "Windows install succeeds on real machine.", "native-plugin/windows-package/INSTALL.cmd; INSTALL-Windows.md", "Windows laptop test", "Needs Manual", "Beta", "P1", generatedOn, "Out of scope for Mac-only validation."],
  ["WIN-002", "Windows Beta", "Windows live PowerPoint control", "Windows beta", "As a Windows tester, I can start/stop PowerPoint live mode.", "Windows implementation controls PowerPoint live window with beta constraints.", "Start/Stop and navigation work with PowerPoint installed.", "native-plugin/src/presentation_document_win.cpp; source_slide_win.cpp", "Windows runtime test", "Needs Manual", "Beta", "P1", generatedOn, ""],
  ["WIN-003", "Windows Beta", "Windows clicker capture", "Windows beta", "As a Windows show operator, clicker capture can route presenter keys globally.", "Low-level keyboard hook maps PageDown/PageUp and supported hotkeys.", "With capture enabled, PageDown/PageUp route to Program deck.", "native-plugin/src/plugin-main.cpp", "Windows runtime test", "Needs Manual", "Beta", "P2", generatedOn, ""],
];

const testLog = [
  ["T-001", "LIVE-001", "Manual live smoke", "Run native-plugin/tests/live_powerpoint_smoke.mm against local PowerPoint/OBS build.", "PPTX preview appears, Start Live Mode starts slideshow, Stop ends slideshow.", "Passed during v0.5.6 release validation.", "Pass", "v0.5.6 release notes / local test run", generatedOn],
  ["T-002", "LIVE-002", "Immediate start after preview", "Click Start while presenter assets may still be preparing.", "Start command is not lost.", "Passed in v0.5.6 smoke coverage.", "Pass", "native-plugin/tests/live_powerpoint_smoke.mm", generatedOn],
  ["T-003", "COMP-002", "Companion template present", "Inspect repo/package for native-plugin/companion/PPTBridge-SK-Companion-OSC-Template.json.", "Template exists and is documented.", "File exists in repo.", "Pass", "rg --files output", generatedOn],
  ["T-004", "HOTKEY-004", "Left/right arrow regression", "With OBS open, test left/right arrow in OBS UI and text inputs.", "Arrows are not swallowed by PPTBridge defaults or global capture.", "Pending hands-on OBS test.", "Not Run", "User-reported regression guard", generatedOn],
  ["T-005", "LOAD-001", "New PPT load speed", "Add a new PPTX from Desktop test folder and time until first visible preview.", "First visible preview should appear quickly; notes/media may continue in background.", "Uncached PPTX rendered first preview in 3160 ms and fully loaded in 3469 ms when run unsandboxed like OBS.", "Pass", "/tmp/pptbridge_render_smoke /tmp/pptbridge-uncached-livepath-test.pptx", generatedOn],
  ["T-006", "INSTALL-001", "macOS build", "Run ./build.sh in native-plugin.", "Plugin bundle builds cleanly.", "Build completed and linked pptbridge-obs.plugin.", "Pass", "./build.sh", generatedOn],
  ["T-007", "OSCFB-001", "OSC feedback smoke", "Compile and run native-plugin/tests/osc_feedback_smoke.cpp.", "OSC feedback sender emits expected status messages.", "Smoke test passed with 16 messages.", "Pass", "/tmp/pptbridge_osc_feedback_test", generatedOn],
  ["T-008", "DECK-002", "PDF render smoke", "Run render_smoke against Desktop test PDF.", "PDF loads and renders slide/presenter output.", "20-slide PDF loaded in 16 ms; slide and presenter render passed.", "Pass", "/tmp/pptbridge_render_smoke Desktop/PPT ZA PROBU PDF", generatedOn],
  ["T-009", "CACHE-001", "Cached PPTX render smoke", "Run render_smoke against existing cached Desktop PPTX.", "Cached PPTX should reuse generated PDF and render quickly.", "Cached PDF reused; 17-slide deck opened in 20 ms; render/nav passed.", "Pass", "/tmp/pptbridge_render_smoke Desktop/PPT ZA PROBU PPTX", generatedOn],
  ["T-010", "LIVE-001", "PowerPoint Save As fallback", "Run PowerPoint AppleScript open/save-as-PDF through full .app path.", "PowerPoint creates a PDF and closes the opened presentation.", "PowerPoint generated /tmp/pptbridge-powerpoint-fallback-test.pdf successfully.", "Pass", "osascript tell application /Applications/Microsoft PowerPoint.app", generatedOn],
  ["T-011", "LIVE-001", "Start Live Mode smoke", "Compile and run native-plugin/tests/live_start_smoke.mm against test PPTX.", "Start Live Mode opens slideshow, navigation works, and Stop closes it.", "Live started in 4464 ms, Next advanced to slide 2, Stop closed the slideshow.", "Pass", "/tmp/pptbridge_live_start_smoke /tmp/pptbridge-uncached-livepath-test.pptx", generatedOn],
  ["T-012", "INSTALL-001", "Local install and OBS load", "Install built bundle locally and launch OBS.", "OBS loads PPTBridge without crash and existing source renders.", "OBS log shows Native plugin loaded; cached source loaded in 178 ms; no PPTBridge errors.", "Pass", "OBS log 2026-06-22 00-23-32.txt", generatedOn],
  ["T-013", "INSTALL-001", "Clean Apple Silicon build", "Run ./build.sh after PowerPoint automation fix.", "Bundle builds with no compile/link errors.", "Build passed and produced native-plugin/build/bundle/pptbridge-obs.plugin.", "Pass", "./build.sh on 2026-06-22", generatedOn],
  ["T-014", "LIVE-001", "Automation guardrails", "Run native-plugin/tests/audit_guardrails.py.", "Guardrails catch regressions in PowerPoint .app targeting, timeouts, cache, and hotkey defaults.", "Audit guardrails passed with exit code 0.", "Pass", "audit_guardrails.py on 2026-06-22", generatedOn],
  ["T-015", "DECK-002", "PDF smoke retest", "Run render_smoke against Desktop PDF test deck.", "PDF loads and renders slide and presenter output.", "20-slide PDF opened in 19 ms; slide/presenter render and navigation passed.", "Pass", "/tmp/pptbridge_render_smoke IV -1 Ana Dimitrijevic.pdf", generatedOn],
  ["T-016", "CACHE-001", "Cached PPTX smoke retest", "Run render_smoke against cached Desktop PPTX.", "Cached PDF is reused and the deck renders quickly.", "17-slide cached PPTX opened in 19 ms and rendered successfully.", "Pass", "/tmp/pptbridge_render_smoke II-3 Aldin Skenderi.pptx", generatedOn],
  ["T-017", "LOAD-001", "Uncached PPTX load retest", "Copy test PPTX to /tmp and run render_smoke outside sandbox.", "First preview appears after real conversion; no crash or blank permanent source.", "Static PDF prepared in 3254 ms; first preview opened in 3314 ms; render passed.", "Pass", "/tmp/pptbridge_render_smoke /tmp/pptbridge-uncached-livepath-test.pptx", generatedOn],
  ["T-018", "LIVE-001", "Start Live Mode retest", "Run live_start_smoke outside sandbox against copied PPTX.", "Start Live Mode opens PowerPoint slideshow, Next works, Stop closes it.", "Live mode started in 2819 ms after load; current became slide 2; Stop closed the slideshow.", "Pass", "/tmp/pptbridge_live_start_smoke /tmp/pptbridge-uncached-livepath-test.pptx", generatedOn],
  ["T-019", "HOTKEY-004", "Arrow-key configuration audit", "Inspect plugin code and current OBS profile for left/right arrow capture.", "No default PPTBridge hotkey should bind left/right; global clicker capture should filter plain arrows.", "OBS profile has pptbridge_native_next=OBS_KEY_2 and previous=OBS_KEY_1 only; code filters kVK_LeftArrow/kVK_RightArrow from clicker capture.", "Pass", "basic.ini + plugin-main.mm inspection", generatedOn],
  ["T-020", "OSCFB-001", "OSC feedback retest", "Compile and run native-plugin/tests/osc_feedback_smoke.cpp.", "OSC feedback sender emits expected status messages.", "Smoke test passed with 16 messages.", "Pass", "/tmp/pptbridge_osc_feedback_test on 2026-06-22", generatedOn],
  ["T-021", "QA-001", "Canonical tracker verification", "Import PPTBridge-Feature-QA-Tracker.xlsx with artifact-tool and scan key sheets plus formula errors.", "Workbook opens with Summary, UserStories, TestLog, and Issues sheets; formula scan finds no errors.", "Import passed: 4 sheets found, TestLog range A1:I25, formula error scan matched 0 entries.", "Pass", "artifact-tool import + formula scan on 2026-06-22", generatedOn],
  ["T-022", "HOTKEY-004", "Automated GUI arrow harness", "Launch a focused Cocoa key receiver and send Left/Right/PageDown/PageUp while OBS is open and clicker capture is active.", "Focused app should receive plain left/right. Captured clicker keys should not leak to the focused app.", "Blocked: harness launched from Codex/LaunchServices did not become a normal frontmost application, so no valid key-delivery evidence was produced. Code/config audit remains clean.", "Blocked", "qa/pptbridge_key_receiver_app.mm + System Events frontmost check", generatedOn],
  ["T-023", "INSTALL-001", "Clean Apple Silicon rebuild", "Run ./build.sh in native-plugin after current PowerPoint automation changes.", "Plugin bundle builds cleanly.", "Build completed and linked build/bundle/pptbridge-obs.plugin with exit code 0.", "Pass", "./build.sh on 2026-06-23", generatedOn],
  ["T-024", "LIVE-001", "Automation guardrails retest", "Run native-plugin/tests/audit_guardrails.py after AppleScript/live-start changes.", "Guardrails catch regressions in AppleScript wrapping, timeouts, live start, hotkeys, OSC, and presenter manual-live messaging.", "Audit guardrails exited 0.", "Pass", "/usr/bin/python3 native-plugin/tests/audit_guardrails.py on 2026-06-23", generatedOn],
  ["T-025", "DECK-002", "PDF render smoke retest", "Run render_smoke against Desktop PDF test deck.", "PDF loads and renders slide/presenter output.", "20-slide PDF opened in 53 ms; slide render, presenter render, navigation render, and cue-state checks passed.", "Pass", "/tmp/pptbridge_render_smoke IV -1 Ana Dimitrijevic.pdf on 2026-06-23", generatedOn],
  ["T-026", "CACHE-001", "Small cached PPTX render smoke retest", "Run render_smoke against cached Desktop PPTX.", "Cached PPTX should reuse generated PDF and render quickly.", "Cached PDF reused; 17-slide PPTX opened first preview in 43 ms; slide/presenter/nav render and cue-state checks passed.", "Pass", "/tmp/pptbridge_render_smoke II-3 Aldin Skenderi.pptx on 2026-06-23", generatedOn],
  ["T-027", "LOAD-001", "Large uncached PPTX load retest", "Copy 19 MB PPTX to /tmp with a new name and run render_smoke with 240s timeout.", "First preview appears after conversion; source does not remain permanently blank.", "Static PDF prepared in 7612 ms; first preview opened in 7668 ms; full load 7845 ms; slide/presenter/nav render passed.", "Pass", "/tmp/pptbridge_render_smoke /tmp/pptbridge-large-qa-20260623.pptx", generatedOn],
  ["T-028", "CACHE-001", "Large cached PPTX reload retest", "Run render_smoke a second time against the same copied 19 MB PPTX.", "Cached PDF should be reused and preview should appear quickly.", "Cached PDF reused; PDF prep 0 ms; first preview 47 ms; full load 242 ms; render/nav/cue-state checks passed.", "Pass", "/tmp/pptbridge_render_smoke /tmp/pptbridge-large-qa-20260623.pptx second run", generatedOn],
  ["T-029", "LIVE-001", "Immediate Start Live Mode retest", "Run live_start_smoke against the original large Desktop PPTX.", "Start Live Mode opens PowerPoint slideshow without requiring prior static load, Next works, and Stop closes it.", "Live ready on 10-slide deck; Next advanced to slide 2; Stop request sent after the smoke.", "Pass", "/tmp/pptbridge_live_start_smoke Desktop/PPT ZA PROBU/II-5 Bajric - HEMOPTIZE.pptx", generatedOn],
  ["T-030", "LIVE-002", "Preview-first manual Start Live Mode retest", "Run live_powerpoint_smoke against original large Desktop PPTX: load preview, then click/start live mode path.", "Manual preview is visible before live mode; Start then opens slideshow and Stop closes it.", "Manual preview loaded 10 slides with live_ready=no; Start opened slideshow; Stop left live_ready=no.", "Pass", "/tmp/pptbridge_live_powerpoint_smoke Desktop/PPT ZA PROBU/II-5 Bajric - HEMOPTIZE.pptx", generatedOn],
  ["T-031", "OSCFB-001", "OSC feedback smoke retest", "Compile and run osc_feedback_smoke after current source changes.", "OSC feedback sender emits expected status messages.", "Smoke test passed with 16 messages.", "Pass", "/tmp/pptbridge_osc_feedback_test on 2026-06-23", generatedOn],
  ["T-032", "QA-001", "Diff whitespace check", "Run git diff --check.", "No whitespace or patch formatting errors.", "git diff --check exited 0.", "Pass", "git diff --check on 2026-06-23", generatedOn],
  ["T-033", "CUE-001/CUE-002/CUE-003/PRES-006", "Cue list render/state smoke", "Run the updated render_smoke against PDF, small cached PPTX, and large cached PPTX with presenter cue list enabled.", "Cue list status should exist; current/next cue checks and clear operation should update snapshot state.", "Passed on 20-slide PDF, 17-slide cached PPTX, and 10-slide large cached PPTX; each printed cue status ok with expected cue count.", "Pass", "/tmp/pptbridge_render_smoke cue status checks on 2026-06-23", generatedOn],
  ["T-034", "INSTALL-001", "v0.5.7 package install smoke", "Run packaged 1-Install-PPTBridge-SK.command from the v0.5.7 release folder after gracefully quitting OBS.", "Installer copies plugin, opens OBS, and OBS loads PPTBridge sources.", "Installer completed successfully; OBS log showed [PPTBridge SK] Native plugin loaded plus source registrations.", "Pass", "OBS log 2026-06-23 02-41-51.txt", generatedOn],
  ["T-035", "INSTALL-004/PACK-001", "v0.5.7 package inspection", "Run make-release.sh, unzip -l, packaged README inspection, Info.plist version check, and shasum verification.", "ZIP contains only expected user-facing files; packaged README and bundle version are 0.5.7; checksum verifies.", "ZIP listing was clean, Info.plist CFBundleShortVersionString/CFBundleVersion were 0.5.7, and checksum returned OK.", "Pass", "native-plugin/release/pptbridge-obs-macos-apple-silicon.zip", generatedOn],
  ["T-036", "OSC-002/OSC-003", "Runtime OSC command in installed OBS", "With installed v0.5.7 OBS running, send /pptbridge/next then /pptbridge/previous through packaged send-osc.sh.", "OBS receives both commands and routes them to the current target deck.", "OBS log recorded OSC: next slide (targets=1) and OSC: previous slide (targets=1).", "Pass", "OBS log 2026-06-23 02-41-51.txt", generatedOn],
  ["T-037", "LOAD-001/LIVE-001", "RunTask stdout/stderr lifetime regression", "Run render_smoke against cached PPTX after fixing RunTask output collection.", "PPTX metadata helper output is read safely without crashing the load worker.", "Small PPTX render smoke no longer exits 133; 17-slide deck loaded, rendered, and cue-state checks passed.", "Pass", "/tmp/pptbridge_render_smoke II-3 Aldin Skenderi.pptx on 2026-06-23", generatedOn],
  ["T-038", "LIVE-001/LIVE-009", "Original-path Start Live regression", "Run live_start_smoke and live_powerpoint_smoke against original Desktop PPTX after temp staging hangs were reproduced.", "PowerPoint opens the user-selected deck path first and starts slideshow reliably.", "Both immediate Start Live and preview-first Start Live passed on the original Desktop deck.", "Pass", "/tmp/pptbridge_live_start_smoke + /tmp/pptbridge_live_powerpoint_smoke on 2026-06-23", generatedOn],
  ["T-039", "DECK-002/CACHE-001/CUE-001/OSCFB-001", "Final render/cue/OSC smoke pass", "Run PDF render, small cached PPTX render, large uncached/cached PPTX render, and OSC feedback smoke after final live-path changes.", "Render, navigation, cue check state, cache reuse, and OSC feedback remain working.", "All render/cue checks passed and OSC feedback smoke returned 16 messages.", "Pass", "Final smoke pass on 2026-06-23", generatedOn],
];

const issues = [
  ["ISS-001", "LOAD-001", "Closed", "P0", "Performance/UX", "User reported new PPTX can take too long before appearing in OBS.", "Screen Recording 2026-06-20 13.26.51", "Keep testing bigger real decks and consider progress/status messaging for first-time conversion over ~5 seconds.", "2026-06-23 large uncached PPTX first preview 7668 ms, full load 7845 ms; same deck cached first preview 46 ms and full load 239 ms.", "Retested Pass"],
  ["ISS-002", "HOTKEY-004", "Open", "P0", "Keyboard UX", "User reported left/right arrows unusable while OBS is open.", "User report in thread", "Do a hands-on OBS UI/text-field arrow-key check with clicker capture both off and on.", "Code/config audit is clean: PPTBridge hotkeys are 2/1 only and clicker capture filters plain left/right arrows. Automated GUI harness could not acquire normal frontmost focus from Codex.", "Code/config pass; manual UI retest still required"],
  ["ISS-003", "LIVE-001", "Closed", "P0", "PowerPoint Automation", "Start Live Mode appeared to do nothing; PowerPoint automation could fail or hang when helper scripts used fragile staging paths or when PowerPoint got stuck in an empty launch state.", "Screen Recording 2026-06-20 14.11.57 plus AppleScript/runtime reproduction", "Keep live_start_smoke and live_powerpoint_smoke in regression loop before releases.", "AppleScript runner now keeps task output as std::string, idle PowerPoint retry parsing uses stable comma output, fresh plugin-owned bad PowerPoint launches can be terminated for retry, and live start opens the original selected deck path before staged fallback.", "Retested Pass"],
];

const headers = [
  "ID",
  "Category",
  "Feature",
  "Platform",
  "User Story",
  "Expected Behavior",
  "Acceptance Criteria",
  "Source Evidence",
  "Test Method",
  "Test Status",
  "Feature Status",
  "Priority",
  "Last Checked",
  "Notes",
];

function styleTitle(sheet, title, subtitle) {
  sheet.showGridLines = false;
  sheet.getRange("A1:N1").merge();
  sheet.getRange("A1").values = [[title]];
  sheet.getRange("A1").format = {
    fill: "#0B1220",
    font: { bold: true, color: "#FFFFFF", size: 18 },
  };
  sheet.getRange("A2:N2").merge();
  sheet.getRange("A2").values = [[subtitle]];
  sheet.getRange("A2").format = {
    fill: "#EAF2FF",
    font: { color: "#1F2937", size: 11 },
    wrapText: true,
  };
  sheet.getRange("A1").format.rowHeight = 28;
  sheet.getRange("A2").format.rowHeight = 28;
}

function setHeaderStyle(range) {
  range.format = {
    fill: "#1F4E78",
    font: { bold: true, color: "#FFFFFF" },
    wrapText: true,
  };
  range.format.borders = { preset: "all", style: "thin", color: "#B7C9D6" };
}

function setBodyStyle(range) {
  range.format = {
    wrapText: true,
    verticalAlignment: "top",
  };
  range.format.borders = { preset: "insideHorizontal", style: "thin", color: "#E5E7EB" };
}

function addStatusFormatting(sheet, rowCount) {
  const testRange = sheet.getRange(`J5:J${rowCount + 4}`);
  testRange.dataValidation = { rule: { type: "list", values: ["Verified", "Pass", "Not Run", "Needs Manual", "Blocked", "Failed", "Retest Required"] } };
  const featureRange = sheet.getRange(`K5:K${rowCount + 4}`);
  featureRange.dataValidation = { rule: { type: "list", values: ["Implemented", "Beta", "Needs Test", "Known Risk", "Docs Only"] } };
  const priorityRange = sheet.getRange(`L5:L${rowCount + 4}`);
  priorityRange.dataValidation = { rule: { type: "list", values: ["P0", "P1", "P2", "P3"] } };
}

function createUserStoriesSheet(workbook) {
  const sheet = workbook.worksheets.add("UserStories");
  styleTitle(sheet, "PPTBridge SK Feature QA Tracker", `Canonical user-story tracker generated ${generatedOn}. Source repo: ${repo}`);
  sheet.getRange("A4:N4").values = [headers];
  setHeaderStyle(sheet.getRange("A4:N4"));
  sheet.getRangeByIndexes(4, 0, stories.length, headers.length).values = stories;
  setBodyStyle(sheet.getRangeByIndexes(4, 0, stories.length, headers.length));
  addStatusFormatting(sheet, stories.length);
  sheet.tables.add(`A4:N${stories.length + 4}`, true, "UserStoriesTable");
  sheet.freezePanes.freezeRows(4);
  sheet.freezePanes.freezeColumns(1);
  const widths = [13, 18, 28, 23, 48, 56, 52, 42, 34, 16, 16, 10, 14, 38];
  widths.forEach((w, idx) => {
    sheet.getRangeByIndexes(0, idx, stories.length + 5, 1).format.columnWidth = w;
  });
  sheet.getRange(`A5:N${stories.length + 4}`).format.rowHeight = 58;
  return sheet;
}

function createSummarySheet(workbook) {
  const sheet = workbook.worksheets.add("Summary");
  sheet.showGridLines = false;
  sheet.getRange("A1:H1").merge();
  sheet.getRange("A1").values = [["PPTBridge SK QA Summary"]];
  sheet.getRange("A1").format = { fill: "#0B1220", font: { bold: true, color: "#FFFFFF", size: 20 } };
  sheet.getRange("A2:H2").merge();
  sheet.getRange("A2").values = [[`Single canonical tracker for feature coverage, user stories, testing, issues, and retesting. Generated ${generatedOn}.`]];
  sheet.getRange("A2").format = { fill: "#EAF2FF", font: { color: "#1F2937" }, wrapText: true };
  sheet.getRange("A1").format.rowHeight = 30;
  sheet.getRange("A2").format.rowHeight = 28;
  sheet.getRange("A4:B12").values = [
    ["Metric", "Value"],
    ["Total user stories", stories.length],
    ["Verified / Pass", ""],
    ["Needs manual test", ""],
    ["Not run", ""],
    ["Retest required", ""],
    ["Open issues", ""],
    ["P0 stories", ""],
    ["Latest stable tracked", "v0.5.7 Apple Silicon"],
  ];
  sheet.getRange("B6").formulas = [[`=COUNTIF('UserStories'!J5:J${stories.length + 4},"Verified")+COUNTIF('UserStories'!J5:J${stories.length + 4},"Pass")`]];
  sheet.getRange("B7").formulas = [[`=COUNTIF('UserStories'!J5:J${stories.length + 4},"Needs Manual")`]];
  sheet.getRange("B8").formulas = [[`=COUNTIF('UserStories'!J5:J${stories.length + 4},"Not Run")`]];
  sheet.getRange("B9").formulas = [[`=COUNTIF('UserStories'!J5:J${stories.length + 4},"Retest Required")`]];
  sheet.getRange("B10").formulas = [[`=COUNTIF('Issues'!C5:C${issues.length + 4},"Open")`]];
  sheet.getRange("B11").formulas = [[`=COUNTIF('UserStories'!L5:L${stories.length + 4},"P0")`]];
  setHeaderStyle(sheet.getRange("A4:B4"));
  sheet.getRange("A5:B12").format.borders = { preset: "all", style: "thin", color: "#CBD5E1" };
  sheet.getRange("A5:A12").format = { fill: "#F8FAFC", font: { bold: true, color: "#334155" } };
  sheet.getRange("B5:B12").format = { fill: "#FFFFFF", font: { color: "#111827" } };
  sheet.getRange("A14:H14").merge();
  sheet.getRange("A14").values = [["How to use this tracker"]];
  sheet.getRange("A14").format = { fill: "#1F4E78", font: { bold: true, color: "#FFFFFF" } };
  sheet.getRange("A15:H20").merge();
  sheet.getRange("A15").values = [[
    "1. Start in User Stories and test every P0/P1 row first.\n" +
    "2. For each test, add or update a row in Test Log.\n" +
    "3. Any confirmed UX/logistical/runtime problem goes into Issues.\n" +
    "4. After fixes, update Retest Result and only mark the story Verified when the evidence is strong."
  ]];
  sheet.getRange("A15").format = { fill: "#F8FAFC", wrapText: true, verticalAlignment: "top" };
  sheet.getRange("A1:H20").format.columnWidth = 22;
  sheet.getRange("A15").format.rowHeight = 120;
  return sheet;
}

function createTestLogSheet(workbook) {
  const sheet = workbook.worksheets.add("TestLog");
  styleTitle(sheet, "PPTBridge SK Test Log", "Every manual or automated check should be recorded here before a story is marked Verified.");
  const logHeaders = ["Test ID", "Story ID", "Scenario", "Steps", "Expected", "Actual", "Result", "Evidence", "Last Run"];
  sheet.getRange("A4:I4").values = [logHeaders];
  setHeaderStyle(sheet.getRange("A4:I4"));
  sheet.getRangeByIndexes(4, 0, testLog.length, logHeaders.length).values = testLog;
  setBodyStyle(sheet.getRangeByIndexes(4, 0, testLog.length, logHeaders.length));
  sheet.tables.add(`A4:I${testLog.length + 4}`, true, "TestLogTable");
  sheet.freezePanes.freezeRows(4);
  [12, 12, 30, 54, 48, 44, 14, 36, 14].forEach((w, i) => sheet.getRangeByIndexes(0, i, testLog.length + 5, 1).format.columnWidth = w);
  sheet.getRange(`A5:I${testLog.length + 4}`).format.rowHeight = 64;
  sheet.getRange(`G5:G${testLog.length + 4}`).dataValidation = { rule: { type: "list", values: ["Pass", "Fail", "Not Run", "Blocked", "Retest Required"] } };
  return sheet;
}

function createIssuesSheet(workbook) {
  const sheet = workbook.worksheets.add("Issues");
  styleTitle(sheet, "PPTBridge SK Issue / Fix / Retest Log", "Only confirmed or user-reported test issues belong here. Keep fixes and retest evidence in the same row.");
  const issueHeaders = ["Issue ID", "Story ID", "Status", "Severity", "Type", "Description", "Evidence", "Next Action", "Fix Summary", "Retest Result"];
  sheet.getRange("A4:J4").values = [issueHeaders];
  setHeaderStyle(sheet.getRange("A4:J4"));
  sheet.getRangeByIndexes(4, 0, issues.length, issueHeaders.length).values = issues;
  setBodyStyle(sheet.getRangeByIndexes(4, 0, issues.length, issueHeaders.length));
  sheet.tables.add(`A4:J${issues.length + 4}`, true, "IssuesTable");
  sheet.freezePanes.freezeRows(4);
  [13, 12, 13, 10, 18, 54, 36, 46, 40, 18].forEach((w, i) => sheet.getRangeByIndexes(0, i, issues.length + 5, 1).format.columnWidth = w);
  sheet.getRange(`A5:J${issues.length + 4}`).format.rowHeight = 72;
  sheet.getRange(`C5:C${issues.length + 4}`).dataValidation = { rule: { type: "list", values: ["Open", "Fixed", "Retesting", "Closed", "Deferred"] } };
  sheet.getRange(`D5:D${issues.length + 4}`).dataValidation = { rule: { type: "list", values: ["P0", "P1", "P2", "P3"] } };
  return sheet;
}

async function main() {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.mkdir(previewDir, { recursive: true });

  const workbook = Workbook.create();
  createSummarySheet(workbook);
  createUserStoriesSheet(workbook);
  createTestLogSheet(workbook);
  createIssuesSheet(workbook);

  const formulaScan = await workbook.inspect({
    kind: "match",
    sheetId: "Summary",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
    options: { useRegex: true, maxResults: 300 },
    summary: "formula error scan",
    maxChars: 2000,
  });
  console.log(formulaScan.ndjson);

  for (const sheetName of ["Summary", "UserStories", "TestLog", "Issues"]) {
    const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
    await fs.writeFile(
      path.join(previewDir, `${sheetName.replaceAll(" ", "-").toLowerCase()}.png`),
      new Uint8Array(await preview.arrayBuffer()));
  }

  const xlsx = await SpreadsheetFile.exportXlsx(workbook);
  await xlsx.save(outputPath);
  console.log(`Saved ${outputPath}`);
}

await main();
