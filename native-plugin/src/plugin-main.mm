#include <obs-module.h>
#include <obs-frontend-api.h>

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

void hotkey_router(void *data, obs_hotkey_id, obs_hotkey_t *, bool pressed)
{
  if (!pressed || !data) {
    return;
  }

  auto document = pptbridge::Registry::Instance().Active();
  if (!document) {
    blog(LOG_WARNING, "[PPTBridge SK] Hotkey pressed, but no active PPTBridge document is selected");
    return;
  }

  switch (*static_cast<HotkeyAction *>(data)) {
  case HotkeyAction::Next:
    blog(LOG_INFO, "[PPTBridge SK] Hotkey: next slide");
    document->Next();
    break;
  case HotkeyAction::Previous:
    blog(LOG_INFO, "[PPTBridge SK] Hotkey: previous slide");
    document->Previous();
    break;
  case HotkeyAction::Black:
    blog(LOG_INFO, "[PPTBridge SK] Hotkey: toggle black");
    document->ToggleBlackScreen();
    break;
  case HotkeyAction::First:
    blog(LOG_INFO, "[PPTBridge SK] Hotkey: first slide");
    document->First();
    break;
  case HotkeyAction::Last:
    blog(LOG_INFO, "[PPTBridge SK] Hotkey: last slide");
    document->Last();
    break;
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
  apply_default_bindings_if_empty(
    g_next_hotkey,
    { OBS_KEY_2, OBS_KEY_PAGEDOWN, OBS_KEY_RIGHT, OBS_KEY_SPACE },
    "Next Slide -> 2 / PageDown / Right / Space");
  apply_default_bindings_if_empty(
    g_previous_hotkey,
    { OBS_KEY_1, OBS_KEY_PAGEUP, OBS_KEY_LEFT },
    "Previous Slide -> 1 / PageUp / Left");
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
