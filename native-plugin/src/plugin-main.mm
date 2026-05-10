#import <AppKit/AppKit.h>

#include <obs-module.h>
#include <obs-frontend-api.h>
#include <util/config-file.h>

#include <cstring>
#include <cstdint>
#include <memory>
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
static bool g_osc_enabled = false;
static uint16_t g_osc_port = kDefaultOscPort;

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

  const int64_t saved_port = config_get_int(config, kOscConfigSection, kOscPortConfigKey);
  g_osc_port = saved_port > 0 && saved_port <= 65535
    ? static_cast<uint16_t>(saved_port)
    : kDefaultOscPort;

  set_osc_enabled(config_get_bool(config, kOscConfigSection, kOscEnabledConfigKey));
}

void save_osc_settings_to_config()
{
  config_t *config = obs_frontend_get_app_config();
  if (!config) {
    return;
  }

  config_set_bool(config, kOscConfigSection, kOscEnabledConfigKey, g_osc_enabled);
  config_set_int(config, kOscConfigSection, kOscPortConfigKey, g_osc_port);
  config_save_safe(config, "tmp", nullptr);
}

void toggle_osc_menu(void *)
{
  set_osc_enabled(!g_osc_enabled);
  blog(LOG_INFO, "[PPTBridge SK] OSC control is now %s", g_osc_enabled ? "enabled" : "disabled");
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
    load_osc_settings_from_config();
    apply_default_hotkeys_if_needed();
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

  blog(LOG_INFO, "[PPTBridge SK] Native plugin loaded");
  return true;
}

void obs_module_unload(void)
{
  set_osc_enabled(false);
  obs_frontend_remove_event_callback(frontend_event_callback, nullptr);
}
