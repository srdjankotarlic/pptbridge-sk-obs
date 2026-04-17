#include <obs-module.h>
#include <obs-frontend-api.h>

#include <cstring>
#include <string>
#include <unordered_set>
#include <vector>

#include "presentation_document.hpp"
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
};

HotkeyAction kNext = HotkeyAction::Next;
HotkeyAction kPrevious = HotkeyAction::Previous;
HotkeyAction kBlack = HotkeyAction::Black;
HotkeyAction kFirst = HotkeyAction::First;
HotkeyAction kLast = HotkeyAction::Last;

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

void hotkey_router(void *data, obs_hotkey_id, obs_hotkey_t *, bool pressed)
{
  if (!pressed || !data) {
    return;
  }

  auto documents = resolve_target_documents();
  if (documents.empty()) {
    blog(LOG_WARNING, "[PPTBridge SK] Hotkey pressed, but no PPTBridge source is in the current scene");
    return;
  }

  const auto action = *static_cast<HotkeyAction *>(data);
  const char *label = "?";
  switch (action) {
  case HotkeyAction::Next:     label = "next slide";      break;
  case HotkeyAction::Previous: label = "previous slide";  break;
  case HotkeyAction::Black:    label = "toggle black";    break;
  case HotkeyAction::First:    label = "first slide";     break;
  case HotkeyAction::Last:     label = "last slide";      break;
  }
  blog(LOG_INFO, "[PPTBridge SK] Hotkey: %s (targets=%zu)", label, documents.size());

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
    }
  }
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

void apply_default_hotkeys_if_needed()
{
  if (g_default_hotkeys_checked) {
    return;
  }

  g_default_hotkeys_checked = true;
  // Defaults are chosen to match a Logitech Spotlight out of the box
  // (Page Down / Right = next, Page Up / Left = previous). We keep the
  // legacy 1/2 bindings and add B / Home / End for blackout / jump-to-first
  // / jump-to-last, which are both standard PowerPoint keystrokes and
  // commonly programmed onto presenter remotes.
  apply_default_bindings_if_empty(
    g_next_hotkey,
    { OBS_KEY_2, OBS_KEY_PAGEDOWN, OBS_KEY_RIGHT, OBS_KEY_SPACE },
    "Next Slide -> 2 / PageDown / Right / Space");
  apply_default_bindings_if_empty(
    g_previous_hotkey,
    { OBS_KEY_1, OBS_KEY_PAGEUP, OBS_KEY_LEFT },
    "Previous Slide -> 1 / PageUp / Left");
  apply_default_bindings_if_empty(
    g_black_hotkey,
    { OBS_KEY_B },
    "Toggle Black -> B");
  apply_default_bindings_if_empty(
    g_first_hotkey,
    { OBS_KEY_HOME },
    "First Slide -> Home");
  apply_default_bindings_if_empty(
    g_last_hotkey,
    { OBS_KEY_END },
    "Last Slide -> End");
}

void frontend_event_callback(enum obs_frontend_event event, void *)
{
  if (event == OBS_FRONTEND_EVENT_FINISHED_LOADING) {
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

  blog(LOG_INFO, "[PPTBridge SK] Native plugin loaded");
  return true;
}

void obs_module_unload(void)
{
  obs_frontend_remove_event_callback(frontend_event_callback, nullptr);
}
