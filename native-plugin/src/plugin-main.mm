#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#include <obs-module.h>
#include <obs-frontend-api.h>
#include <util/config-file.h>

#include <cstring>
#include <cstdint>
#include <cctype>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

#include "presentation_document.hpp"
#include "pptbridge_osc_server.hpp"
#include "pptbridge_registry.hpp"

OBS_MODULE_USE_DEFAULT_LOCALE("pptbridge-obs", "en-US")

namespace {

constexpr uint32_t kTargetObsApiVersion = ((32u << 24) | (0u << 16) | 3u);
static obs_module_t *g_obs_module_pointer = nullptr;
static obs_hotkey_id g_next_hotkey = OBS_INVALID_HOTKEY_ID;
static obs_hotkey_id g_previous_hotkey = OBS_INVALID_HOTKEY_ID;
static obs_hotkey_id g_black_hotkey = OBS_INVALID_HOTKEY_ID;
static obs_hotkey_id g_first_hotkey = OBS_INVALID_HOTKEY_ID;
static obs_hotkey_id g_last_hotkey = OBS_INVALID_HOTKEY_ID;
static bool g_default_hotkeys_checked = false;
constexpr uint16_t kDefaultOscPort = 57130;
constexpr const char *kOscConfigSection = "PPTBridgeSK";
constexpr const char *kOscEnabledConfigKey = "OscEnabled";
constexpr const char *kOscPortConfigKey = "OscPort";
constexpr const char *kClickerCaptureConfigKey = "ClickerCaptureEnabled";
static bool g_osc_enabled = false;
static uint16_t g_osc_port = kDefaultOscPort;
static bool g_clicker_capture_enabled = false;
static CFMachPortRef g_clicker_event_tap = nullptr;
static CFRunLoopSourceRef g_clicker_run_loop_source = nullptr;
static std::mutex g_clicker_bindings_mutex;
static std::unordered_set<CGKeyCode> g_clicker_swallowed_keys;

}  // namespace

MODULE_EXPORT void obs_module_set_pointer(obs_module_t *module)
{
  g_obs_module_pointer = module;
}

obs_module_t *obs_current_module(void)
{
  return g_obs_module_pointer;
}

MODULE_EXPORT uint32_t obs_module_ver(void)
{
  return kTargetObsApiVersion;
}

namespace pptbridge {
obs_source_info *pptbridge_slide_source_info();
obs_source_info *pptbridge_presenter_source_info();
}

namespace {

enum class HotkeyAction {
  Next,
  Previous,
  Black,
  First,
  Last,
  Reload,
};

HotkeyAction kNext = HotkeyAction::Next;
HotkeyAction kPrevious = HotkeyAction::Previous;
HotkeyAction kBlack = HotkeyAction::Black;
HotkeyAction kFirst = HotkeyAction::First;
HotkeyAction kLast = HotkeyAction::Last;

struct ClickerBinding {
  CGKeyCode key_code = 0;
  CGEventFlags modifiers = 0;
  HotkeyAction action = HotkeyAction::Next;
};

std::vector<ClickerBinding> g_clicker_bindings;

const char *action_label(HotkeyAction action)
{
  switch (action) {
  case HotkeyAction::Next:     return "next slide";
  case HotkeyAction::Previous: return "previous slide";
  case HotkeyAction::Black:    return "toggle black";
  case HotkeyAction::First:    return "first slide";
  case HotkeyAction::Last:     return "last slide";
  case HotkeyAction::Reload:   return "reload presentation";
  }
  return "?";
}

bool obs_application_is_active()
{
  return [[NSRunningApplication currentApplication] isActive];
}

bool is_pptbridge_source(obs_source_t *source)
{
  if (!source) {
    return false;
  }
  const char *source_id = obs_source_get_id(source);
  if (!source_id) {
    return false;
  }
  return std::strcmp(source_id, "pptbridge_slide_source") == 0 ||
         std::strcmp(source_id, "pptbridge_presenter_source") == 0;
}

struct SceneCollector {
  std::vector<std::string> paths;
  std::unordered_set<std::string> seen;
};

bool collect_pptbridge_from_item(obs_scene_t *, obs_sceneitem_t *item, void *user_data)
{
  if (!item || !user_data) {
    return true;
  }
  obs_source_t *source = obs_sceneitem_get_source(item);
  if (!source) {
    return true;
  }

  // Walk nested group children as well so a pptbridge source inside a
  // group scene still routes hotkeys correctly.
  if (obs_source_is_group(source)) {
    obs_scene_t *group = obs_group_from_source(source);
    if (group) {
      obs_scene_enum_items(group, collect_pptbridge_from_item, user_data);
    }
  }

  if (!is_pptbridge_source(source)) {
    return true;
  }

  auto *collector = static_cast<SceneCollector *>(user_data);
  obs_data_t *settings = obs_source_get_settings(source);
  const char *path = settings ? obs_data_get_string(settings, "pptx_path") : nullptr;
  std::string path_str = path ? path : "";
  if (settings) {
    obs_data_release(settings);
  }
  if (path_str.empty()) {
    return true;
  }
  if (collector->seen.insert(path_str).second) {
    collector->paths.push_back(std::move(path_str));
  }
  return true;
}

// Scene-aware hotkey dispatch.
//
// A single Logitech Spotlight (or OBS hotkey) press routes to whichever
// PPTBridge source is currently in the program scene — so a show with
// multiple decks (one per scene) routes clicks to the right deck without
// the presenter having to focus anything. If the program scene has no
// PPTBridge source we fall back to the "last active" document for
// backwards compatibility with single-deck setups.
std::vector<std::shared_ptr<pptbridge::PresentationDocument>> resolve_target_documents()
{
  std::vector<std::shared_ptr<pptbridge::PresentationDocument>> documents;

  obs_source_t *program_source = obs_frontend_get_current_scene();
  if (program_source) {
    obs_scene_t *scene = obs_scene_from_source(program_source);
    if (!scene && obs_source_is_group(program_source)) {
      scene = obs_group_from_source(program_source);
    }
    SceneCollector collector;
    if (scene) {
      obs_scene_enum_items(scene, collect_pptbridge_from_item, &collector);
    }
    obs_source_release(program_source);

    for (const auto &path : collector.paths) {
      if (auto document = pptbridge::Registry::Instance().Acquire(path)) {
        documents.push_back(std::move(document));
      }
    }
  }

  if (documents.empty()) {
    if (auto fallback = pptbridge::Registry::Instance().Active()) {
      documents.push_back(std::move(fallback));
    }
  }

  return documents;
}

void dispatch_action_to_documents(HotkeyAction action, const char *control_source)
{
  auto documents = resolve_target_documents();
  if (documents.empty()) {
    blog(LOG_WARNING, "[PPTBridge SK] %s control received, but no PPTBridge source is in the current scene",
         control_source ? control_source : "Remote");
    return;
  }

  blog(LOG_INFO, "[PPTBridge SK] %s: %s (targets=%zu)",
       control_source ? control_source : "Remote",
       action_label(action),
       documents.size());

  for (const auto &document : documents) {
    if (!document) {
      continue;
    }
    switch (action) {
    case HotkeyAction::Next:     document->Next();             break;
    case HotkeyAction::Previous: document->Previous();         break;
    case HotkeyAction::Black:    document->ToggleBlackScreen(); break;
    case HotkeyAction::First:    document->First();            break;
    case HotkeyAction::Last:     document->Last();             break;
    case HotkeyAction::Reload:   document->ReloadAsync();      break;
    }
  }
}

void hotkey_router(void *data, obs_hotkey_id, obs_hotkey_t *, bool pressed)
{
  if (!pressed || !data) {
    return;
  }
  if (!obs_application_is_active()) {
    return;
  }

  dispatch_action_to_documents(*static_cast<HotkeyAction *>(data), "Hotkey");
}

void queued_clicker_action_task(void *param)
{
  std::unique_ptr<HotkeyAction> action(static_cast<HotkeyAction *>(param));
  if (!action) {
    return;
  }
  dispatch_action_to_documents(*action, "Spotlight/Clicker Capture");
}

HotkeyAction hotkey_action_from_osc(pptbridge::OscAction action)
{
  switch (action) {
  case pptbridge::OscAction::Next:     return HotkeyAction::Next;
  case pptbridge::OscAction::Previous: return HotkeyAction::Previous;
  case pptbridge::OscAction::Black:    return HotkeyAction::Black;
  case pptbridge::OscAction::First:    return HotkeyAction::First;
  case pptbridge::OscAction::Last:     return HotkeyAction::Last;
  case pptbridge::OscAction::Reload:   return HotkeyAction::Reload;
  }
  return HotkeyAction::Next;
}

std::string normalize_key_name(const char *name)
{
  std::string value = name ? name : "";
  constexpr const char *prefix = "OBS_KEY_";
  if (value.rfind(prefix, 0) == 0) {
    value.erase(0, std::strlen(prefix));
  }

  std::string normalized;
  normalized.reserve(value.size());
  for (unsigned char ch : value) {
    if (ch == '_' || ch == '-' || ch == ' ') {
      continue;
    }
    normalized.push_back(static_cast<char>(std::toupper(ch)));
  }
  return normalized;
}

bool key_name_to_cg_key_code(const char *name, CGKeyCode &out_key_code)
{
  const std::string key = normalize_key_name(name);
  if (key == "1") { out_key_code = kVK_ANSI_1; return true; }
  if (key == "2") { out_key_code = kVK_ANSI_2; return true; }
  if (key == "3") { out_key_code = kVK_ANSI_3; return true; }
  if (key == "4") { out_key_code = kVK_ANSI_4; return true; }
  if (key == "5") { out_key_code = kVK_ANSI_5; return true; }
  if (key == "6") { out_key_code = kVK_ANSI_6; return true; }
  if (key == "7") { out_key_code = kVK_ANSI_7; return true; }
  if (key == "8") { out_key_code = kVK_ANSI_8; return true; }
  if (key == "9") { out_key_code = kVK_ANSI_9; return true; }
  if (key == "0") { out_key_code = kVK_ANSI_0; return true; }
  if (key == "A") { out_key_code = kVK_ANSI_A; return true; }
  if (key == "B") { out_key_code = kVK_ANSI_B; return true; }
  if (key == "C") { out_key_code = kVK_ANSI_C; return true; }
  if (key == "D") { out_key_code = kVK_ANSI_D; return true; }
  if (key == "E") { out_key_code = kVK_ANSI_E; return true; }
  if (key == "F") { out_key_code = kVK_ANSI_F; return true; }
  if (key == "G") { out_key_code = kVK_ANSI_G; return true; }
  if (key == "H") { out_key_code = kVK_ANSI_H; return true; }
  if (key == "I") { out_key_code = kVK_ANSI_I; return true; }
  if (key == "J") { out_key_code = kVK_ANSI_J; return true; }
  if (key == "K") { out_key_code = kVK_ANSI_K; return true; }
  if (key == "L") { out_key_code = kVK_ANSI_L; return true; }
  if (key == "M") { out_key_code = kVK_ANSI_M; return true; }
  if (key == "N") { out_key_code = kVK_ANSI_N; return true; }
  if (key == "O") { out_key_code = kVK_ANSI_O; return true; }
  if (key == "P") { out_key_code = kVK_ANSI_P; return true; }
  if (key == "Q") { out_key_code = kVK_ANSI_Q; return true; }
  if (key == "R") { out_key_code = kVK_ANSI_R; return true; }
  if (key == "S") { out_key_code = kVK_ANSI_S; return true; }
  if (key == "T") { out_key_code = kVK_ANSI_T; return true; }
  if (key == "U") { out_key_code = kVK_ANSI_U; return true; }
  if (key == "V") { out_key_code = kVK_ANSI_V; return true; }
  if (key == "W") { out_key_code = kVK_ANSI_W; return true; }
  if (key == "X") { out_key_code = kVK_ANSI_X; return true; }
  if (key == "Y") { out_key_code = kVK_ANSI_Y; return true; }
  if (key == "Z") { out_key_code = kVK_ANSI_Z; return true; }
  if (key == "SPACE") { out_key_code = kVK_Space; return true; }
  if (key == "LEFT") { out_key_code = kVK_LeftArrow; return true; }
  if (key == "RIGHT") { out_key_code = kVK_RightArrow; return true; }
  if (key == "UP") { out_key_code = kVK_UpArrow; return true; }
  if (key == "DOWN") { out_key_code = kVK_DownArrow; return true; }
  if (key == "PAGEUP" || key == "PRIOR") { out_key_code = kVK_PageUp; return true; }
  if (key == "PAGEDOWN" || key == "NEXT") { out_key_code = kVK_PageDown; return true; }
  if (key == "HOME") { out_key_code = kVK_Home; return true; }
  if (key == "END") { out_key_code = kVK_End; return true; }
  if (key == "RETURN" || key == "ENTER") { out_key_code = kVK_Return; return true; }
  if (key == "ESCAPE" || key == "ESC") { out_key_code = kVK_Escape; return true; }
  return false;
}

CGEventFlags modifier_flags_from_hotkey_item(obs_data_t *item)
{
  CGEventFlags modifiers = 0;
  if (obs_data_get_bool(item, "shift")) {
    modifiers |= kCGEventFlagMaskShift;
  }
  if (obs_data_get_bool(item, "control")) {
    modifiers |= kCGEventFlagMaskControl;
  }
  if (obs_data_get_bool(item, "alt")) {
    modifiers |= kCGEventFlagMaskAlternate;
  }
  if (obs_data_get_bool(item, "command")) {
    modifiers |= kCGEventFlagMaskCommand;
  }
  return modifiers;
}

void append_clicker_bindings_from_hotkey(
  obs_hotkey_id id,
  HotkeyAction action,
  std::vector<ClickerBinding> &bindings)
{
  if (id == OBS_INVALID_HOTKEY_ID) {
    return;
  }

  obs_data_array_t *saved = obs_hotkey_save(id);
  if (!saved) {
    return;
  }

  for (size_t i = 0; i < obs_data_array_count(saved); ++i) {
    obs_data_t *item = obs_data_array_item(saved, i);
    if (!item) {
      continue;
    }

    CGKeyCode key_code = 0;
    const char *key_name = obs_data_get_string(item, "key");
    if (key_name_to_cg_key_code(key_name, key_code)) {
      bindings.push_back(ClickerBinding{
        key_code,
        modifier_flags_from_hotkey_item(item),
        action,
      });
    } else if (key_name && *key_name) {
      blog(LOG_WARNING,
        "[PPTBridge SK] Spotlight/Clicker Capture cannot map OBS hotkey key '%s' yet",
        key_name);
    }
    obs_data_release(item);
  }

  obs_data_array_release(saved);
}

void append_clicker_binding_if_missing(
  std::vector<ClickerBinding> &bindings,
  CGKeyCode key_code,
  CGEventFlags modifiers,
  HotkeyAction action)
{
  for (const auto &binding : bindings) {
    if (binding.key_code == key_code && binding.modifiers == modifiers && binding.action == action) {
      return;
    }
  }

  bindings.push_back(ClickerBinding{ key_code, modifiers, action });
}

bool is_plain_typing_key_for_clicker(CGKeyCode key_code, CGEventFlags modifiers)
{
  if (modifiers != 0) {
    return false;
  }

  // Stage clicker capture is global, so plain typing keys stay reserved for
  // the operator's focused app. Presenter remotes still work through nav keys.
  switch (key_code) {
  case kVK_Space:
  case kVK_Return:
  case kVK_ANSI_KeypadEnter:
  case kVK_Tab:
  case kVK_Delete:
  case kVK_ANSI_0:
  case kVK_ANSI_1:
  case kVK_ANSI_2:
  case kVK_ANSI_3:
  case kVK_ANSI_4:
  case kVK_ANSI_5:
  case kVK_ANSI_6:
  case kVK_ANSI_7:
  case kVK_ANSI_8:
  case kVK_ANSI_9:
  case kVK_ANSI_A:
  case kVK_ANSI_B:
  case kVK_ANSI_C:
  case kVK_ANSI_D:
  case kVK_ANSI_E:
  case kVK_ANSI_F:
  case kVK_ANSI_G:
  case kVK_ANSI_H:
  case kVK_ANSI_I:
  case kVK_ANSI_J:
  case kVK_ANSI_K:
  case kVK_ANSI_L:
  case kVK_ANSI_M:
  case kVK_ANSI_N:
  case kVK_ANSI_O:
  case kVK_ANSI_P:
  case kVK_ANSI_Q:
  case kVK_ANSI_R:
  case kVK_ANSI_S:
  case kVK_ANSI_T:
  case kVK_ANSI_U:
  case kVK_ANSI_V:
  case kVK_ANSI_W:
  case kVK_ANSI_X:
  case kVK_ANSI_Y:
  case kVK_ANSI_Z:
    return true;
  default:
    return false;
  }
}

void append_clicker_bindings_from_hotkey_without_plain_typing_keys(
  obs_hotkey_id id,
  HotkeyAction action,
  std::vector<ClickerBinding> &bindings)
{
  const size_t before = bindings.size();
  append_clicker_bindings_from_hotkey(id, action, bindings);
  size_t write_index = before;
  for (size_t read_index = before; read_index < bindings.size(); ++read_index) {
    const auto &binding = bindings[read_index];
    if (is_plain_typing_key_for_clicker(binding.key_code, binding.modifiers)) {
      continue;
    }
    if (write_index != read_index) {
      bindings[write_index] = binding;
    }
    ++write_index;
  }
  bindings.resize(write_index);
}

void append_default_clicker_bindings(std::vector<ClickerBinding> &bindings)
{
  // Presenter remotes such as Logitech Spotlight usually send these keys.
  // Normal OBS hotkeys stay intentionally narrow (2/1), but Stage Clicker
  // Capture should work out-of-the-box while another app has focus.
  append_clicker_binding_if_missing(bindings, kVK_PageDown, 0, HotkeyAction::Next);
  append_clicker_binding_if_missing(bindings, kVK_RightArrow, 0, HotkeyAction::Next);
  append_clicker_binding_if_missing(bindings, kVK_PageUp, 0, HotkeyAction::Previous);
  append_clicker_binding_if_missing(bindings, kVK_LeftArrow, 0, HotkeyAction::Previous);
}

std::vector<ClickerBinding> collect_clicker_bindings_from_obs_hotkeys()
{
  std::vector<ClickerBinding> bindings;
  append_default_clicker_bindings(bindings);
  append_clicker_bindings_from_hotkey_without_plain_typing_keys(g_next_hotkey, HotkeyAction::Next, bindings);
  append_clicker_bindings_from_hotkey_without_plain_typing_keys(g_previous_hotkey, HotkeyAction::Previous, bindings);
  append_clicker_bindings_from_hotkey_without_plain_typing_keys(g_black_hotkey, HotkeyAction::Black, bindings);
  append_clicker_bindings_from_hotkey_without_plain_typing_keys(g_first_hotkey, HotkeyAction::First, bindings);
  append_clicker_bindings_from_hotkey_without_plain_typing_keys(g_last_hotkey, HotkeyAction::Last, bindings);
  return bindings;
}

void refresh_clicker_bindings()
{
  auto bindings = collect_clicker_bindings_from_obs_hotkeys();
  {
    std::lock_guard<std::mutex> lock(g_clicker_bindings_mutex);
    g_clicker_bindings = std::move(bindings);
    g_clicker_swallowed_keys.clear();
  }
  blog(LOG_INFO,
    "[PPTBridge SK] Spotlight/Clicker Capture loaded %zu OBS hotkey binding(s)",
    g_clicker_bindings.size());
}

bool clicker_binding_matches(const ClickerBinding &binding, CGKeyCode key_code, CGEventFlags flags)
{
  if (binding.key_code != key_code) {
    return false;
  }

  constexpr CGEventFlags kRelevantFlags =
    kCGEventFlagMaskShift |
    kCGEventFlagMaskControl |
    kCGEventFlagMaskAlternate |
    kCGEventFlagMaskCommand;
  return (flags & kRelevantFlags) == binding.modifiers;
}

CGEventRef clicker_event_tap_callback(
  CGEventTapProxy,
  CGEventType type,
  CGEventRef event,
  void *)
{
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    if (g_clicker_event_tap) {
      CGEventTapEnable(g_clicker_event_tap, true);
    }
    return event;
  }

  if (type != kCGEventKeyDown && type != kCGEventKeyUp) {
    return event;
  }

  const auto key_code =
    static_cast<CGKeyCode>(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode));
  const auto flags = CGEventGetFlags(event);

  if (type == kCGEventKeyUp) {
    std::lock_guard<std::mutex> lock(g_clicker_bindings_mutex);
    const bool swallowed = g_clicker_swallowed_keys.erase(key_code) > 0;
    return swallowed ? nullptr : event;
  }

  HotkeyAction matched_action = HotkeyAction::Next;
  bool matched = false;
  {
    std::lock_guard<std::mutex> lock(g_clicker_bindings_mutex);
    for (const auto &binding : g_clicker_bindings) {
      if (clicker_binding_matches(binding, key_code, flags)) {
        matched_action = binding.action;
        g_clicker_swallowed_keys.insert(key_code);
        matched = true;
        break;
      }
    }
  }

  if (!matched) {
    return event;
  }

  if (CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0) {
    return nullptr;
  }

  auto *queued = new HotkeyAction(matched_action);
  obs_queue_task(OBS_TASK_UI, queued_clicker_action_task, queued, false);
  return nullptr;
}

void stop_clicker_capture()
{
  if (g_clicker_event_tap) {
    CGEventTapEnable(g_clicker_event_tap, false);
  }
  if (g_clicker_run_loop_source) {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), g_clicker_run_loop_source, kCFRunLoopCommonModes);
    CFRelease(g_clicker_run_loop_source);
    g_clicker_run_loop_source = nullptr;
  }
  if (g_clicker_event_tap) {
    CFRelease(g_clicker_event_tap);
    g_clicker_event_tap = nullptr;
  }
  {
    std::lock_guard<std::mutex> lock(g_clicker_bindings_mutex);
    g_clicker_swallowed_keys.clear();
  }
}

bool start_clicker_capture()
{
  stop_clicker_capture();
  refresh_clicker_bindings();

  {
    std::lock_guard<std::mutex> lock(g_clicker_bindings_mutex);
    if (g_clicker_bindings.empty()) {
      blog(LOG_WARNING,
        "[PPTBridge SK] Spotlight/Clicker Capture has no supported PPTBridge hotkeys to capture");
      return false;
    }
  }

  NSDictionary *trust_options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES };
  if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)trust_options)) {
    blog(LOG_WARNING,
      "[PPTBridge SK] Spotlight/Clicker Capture needs macOS Accessibility/Input Monitoring permission for OBS");
  }

  const CGEventMask event_mask =
    CGEventMaskBit(kCGEventKeyDown) |
    CGEventMaskBit(kCGEventKeyUp);
  g_clicker_event_tap = CGEventTapCreate(
    kCGSessionEventTap,
    kCGHeadInsertEventTap,
    kCGEventTapOptionDefault,
    event_mask,
    clicker_event_tap_callback,
    nullptr);

  if (!g_clicker_event_tap) {
    blog(LOG_WARNING,
      "[PPTBridge SK] Spotlight/Clicker Capture could not start. Grant OBS Accessibility/Input Monitoring permission, then toggle it again.");
    return false;
  }

  g_clicker_run_loop_source =
    CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_clicker_event_tap, 0);
  if (!g_clicker_run_loop_source) {
    stop_clicker_capture();
    blog(LOG_WARNING, "[PPTBridge SK] Spotlight/Clicker Capture could not create a run loop source");
    return false;
  }

  CFRunLoopAddSource(CFRunLoopGetMain(), g_clicker_run_loop_source, kCFRunLoopCommonModes);
  CGEventTapEnable(g_clicker_event_tap, true);
  return true;
}

void set_clicker_capture_enabled(bool enabled)
{
  if (enabled) {
    g_clicker_capture_enabled = start_clicker_capture();
    return;
  }

  stop_clicker_capture();
  g_clicker_capture_enabled = false;
}

void queued_osc_action_task(void *param)
{
  std::unique_ptr<HotkeyAction> action(static_cast<HotkeyAction *>(param));
  if (!action) {
    return;
  }
  dispatch_action_to_documents(*action, "OSC");
}

void osc_action_callback(pptbridge::OscAction action)
{
  auto *queued = new HotkeyAction(hotkey_action_from_osc(action));
  obs_queue_task(OBS_TASK_UI, queued_osc_action_task, queued, false);
}

void set_osc_enabled(bool enabled)
{
  if (enabled) {
    if (pptbridge::StartOscServer(g_osc_port, osc_action_callback)) {
      g_osc_enabled = true;
    } else {
      g_osc_enabled = false;
    }
    return;
  }

  if (pptbridge::OscServerRunning()) {
    pptbridge::StopOscServer();
  }
  g_osc_enabled = false;
}

void load_osc_settings_from_config()
{
  config_t *config = obs_frontend_get_app_config();
  if (!config) {
    return;
  }

  config_set_default_bool(config, kOscConfigSection, kOscEnabledConfigKey, false);
  config_set_default_int(config, kOscConfigSection, kOscPortConfigKey, kDefaultOscPort);
  config_set_default_bool(config, kOscConfigSection, kClickerCaptureConfigKey, false);

  const int64_t saved_port = config_get_int(config, kOscConfigSection, kOscPortConfigKey);
  g_osc_port = saved_port > 0 && saved_port <= 65535
    ? static_cast<uint16_t>(saved_port)
    : kDefaultOscPort;

  set_osc_enabled(config_get_bool(config, kOscConfigSection, kOscEnabledConfigKey));
  set_clicker_capture_enabled(config_get_bool(config, kOscConfigSection, kClickerCaptureConfigKey));
}

void save_osc_settings_to_config()
{
  config_t *config = obs_frontend_get_app_config();
  if (!config) {
    return;
  }

  config_set_bool(config, kOscConfigSection, kOscEnabledConfigKey, g_osc_enabled);
  config_set_int(config, kOscConfigSection, kOscPortConfigKey, g_osc_port);
  config_set_bool(config, kOscConfigSection, kClickerCaptureConfigKey, g_clicker_capture_enabled);
  config_save_safe(config, "tmp", nullptr);
}

void toggle_osc_menu(void *)
{
  set_osc_enabled(!g_osc_enabled);
  blog(LOG_INFO, "[PPTBridge SK] OSC control is now %s", g_osc_enabled ? "enabled" : "disabled");
  save_osc_settings_to_config();
}

void toggle_clicker_capture_menu(void *)
{
  set_clicker_capture_enabled(!g_clicker_capture_enabled);
  blog(LOG_INFO,
    "[PPTBridge SK] Spotlight/Clicker Capture is now %s",
    g_clicker_capture_enabled ? "enabled" : "disabled");
  save_osc_settings_to_config();
}

void apply_default_bindings_if_empty(obs_hotkey_id id, const std::vector<obs_key_t> &keys, const char *log_label)
{
  if (id == OBS_INVALID_HOTKEY_ID) {
    return;
  }

  obs_data_array_t *saved = obs_hotkey_save(id);
  const size_t count = saved ? obs_data_array_count(saved) : 0;
  if (saved) {
    obs_data_array_release(saved);
  }

  if (count != 0) {
    return;
  }

  std::vector<obs_key_combination_t> combos;
  combos.reserve(keys.size());
  for (const auto key : keys) {
    obs_key_combination_t combo = {};
    combo.modifiers = 0;
    combo.key = key;
    combos.push_back(combo);
  }

  obs_hotkey_load_bindings(id, combos.data(), combos.size());
  blog(LOG_INFO, "[PPTBridge SK] Applied default hotkey: %s", log_label);
}

bool saved_bindings_match_keys(obs_hotkey_id id, const std::vector<obs_key_t> &keys)
{
  if (id == OBS_INVALID_HOTKEY_ID) {
    return false;
  }

  obs_data_array_t *saved = obs_hotkey_save(id);
  if (!saved) {
    return false;
  }

  bool matches = obs_data_array_count(saved) == keys.size();
  std::unordered_set<std::string> expected;
  if (matches) {
    for (const auto key : keys) {
      const char *name = obs_key_to_name(key);
      if (!name) {
        matches = false;
        break;
      }
      expected.insert(name);
    }
  }

  for (size_t i = 0; matches && i < obs_data_array_count(saved); ++i) {
    obs_data_t *item = obs_data_array_item(saved, i);
    if (!item) {
      matches = false;
      break;
    }

    const bool has_modifier =
      obs_data_get_bool(item, "shift") ||
      obs_data_get_bool(item, "control") ||
      obs_data_get_bool(item, "alt") ||
      obs_data_get_bool(item, "command");
    const char *key_name = obs_data_get_string(item, "key");
    if (has_modifier || !key_name || expected.erase(key_name) != 1) {
      matches = false;
    }
    obs_data_release(item);
  }

  obs_data_array_release(saved);
  return matches && expected.empty();
}

void load_key_bindings(obs_hotkey_id id, const std::vector<obs_key_t> &keys)
{
  std::vector<obs_key_combination_t> combos;
  combos.reserve(keys.size());
  for (const auto key : keys) {
    obs_key_combination_t combo = {};
    combo.modifiers = 0;
    combo.key = key;
    combos.push_back(combo);
  }
  obs_hotkey_load_bindings(id, combos.empty() ? nullptr : combos.data(), combos.size());
}

void migrate_legacy_default_bindings(
  obs_hotkey_id id,
  const std::vector<obs_key_t> &legacy_keys,
  const std::vector<obs_key_t> &new_keys,
  const char *log_label)
{
  if (!saved_bindings_match_keys(id, legacy_keys)) {
    return;
  }
  load_key_bindings(id, new_keys);
  blog(LOG_INFO, "[PPTBridge SK] Migrated default hotkey: %s", log_label);
}

void apply_default_hotkeys_if_needed()
{
  if (g_default_hotkeys_checked) {
    return;
  }

  g_default_hotkeys_checked = true;
  // Keep first-launch defaults intentionally narrow so typing in another app
  // cannot accidentally drive a deck when OBS global hotkeys are enabled.
  migrate_legacy_default_bindings(
    g_next_hotkey,
    { OBS_KEY_2, OBS_KEY_PAGEDOWN, OBS_KEY_RIGHT, OBS_KEY_SPACE },
    { OBS_KEY_2 },
    "Next Slide -> 2");
  migrate_legacy_default_bindings(
    g_previous_hotkey,
    { OBS_KEY_1, OBS_KEY_PAGEUP, OBS_KEY_LEFT },
    { OBS_KEY_1 },
    "Previous Slide -> 1");
  migrate_legacy_default_bindings(
    g_black_hotkey,
    { OBS_KEY_B },
    {},
    "Toggle Black -> unbound");
  migrate_legacy_default_bindings(
    g_first_hotkey,
    { OBS_KEY_HOME },
    {},
    "First Slide -> unbound");
  migrate_legacy_default_bindings(
    g_last_hotkey,
    { OBS_KEY_END },
    {},
    "Last Slide -> unbound");

  apply_default_bindings_if_empty(
    g_next_hotkey,
    { OBS_KEY_2 },
    "Next Slide -> 2");
  apply_default_bindings_if_empty(
    g_previous_hotkey,
    { OBS_KEY_1 },
    "Previous Slide -> 1");
}

void frontend_event_callback(enum obs_frontend_event event, void *)
{
  if (event == OBS_FRONTEND_EVENT_FINISHED_LOADING) {
    apply_default_hotkeys_if_needed();
    load_osc_settings_from_config();
  }
}

}  // namespace

MODULE_EXPORT const char *obs_module_description(void)
{
  return "PPTBridge SK for OBS by Srđan Kotarlić";
}

bool obs_module_load(void)
{
  obs_register_source(pptbridge::pptbridge_slide_source_info());
  obs_register_source(pptbridge::pptbridge_presenter_source_info());

  g_next_hotkey = obs_hotkey_register_frontend(
    "pptbridge_native_next",
    "PPTBridge SK: Next Slide",
    hotkey_router,
    &kNext);
  g_previous_hotkey = obs_hotkey_register_frontend(
    "pptbridge_native_previous",
    "PPTBridge SK: Previous Slide",
    hotkey_router,
    &kPrevious);
  g_black_hotkey = obs_hotkey_register_frontend(
    "pptbridge_native_black",
    "PPTBridge SK: Toggle Black Screen",
    hotkey_router,
    &kBlack);
  g_first_hotkey = obs_hotkey_register_frontend(
    "pptbridge_native_first",
    "PPTBridge SK: First Slide",
    hotkey_router,
    &kFirst);
  g_last_hotkey = obs_hotkey_register_frontend(
    "pptbridge_native_last",
    "PPTBridge SK: Last Slide",
    hotkey_router,
    &kLast);

  obs_frontend_add_event_callback(frontend_event_callback, nullptr);
  obs_frontend_add_tools_menu_item("PPTBridge SK: Toggle Local OSC Control", toggle_osc_menu, nullptr);
  obs_frontend_add_tools_menu_item("PPTBridge SK: Toggle Spotlight/Clicker Capture", toggle_clicker_capture_menu, nullptr);

  blog(LOG_INFO, "[PPTBridge SK] Native plugin loaded");
  return true;
}

void obs_module_unload(void)
{
  set_clicker_capture_enabled(false);
  set_osc_enabled(false);
  obs_frontend_remove_event_callback(frontend_event_callback, nullptr);
}
