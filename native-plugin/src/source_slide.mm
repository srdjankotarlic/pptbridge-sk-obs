#import "source_shared.hpp"

#include <functional>
#include <obs-frontend-api.h>

#include "pptbridge_registry.hpp"

namespace pptbridge {

namespace {

constexpr const char *kHotkeyHelp =
  "Slide control:\n"
  "1. Open Settings > Hotkeys\n"
  "2. Bind PPTBridge SK: Next Slide / Previous Slide\n"
  "3. For a clicker, use Right Arrow or Page Down for next, Left Arrow or Page Up for previous\n"
  "4. Use the buttons below for quick testing inside OBS";

void refresh_texture_if_needed(SourceContext *context)
{
  if (!context || !context->document || context->width == 0 || context->height == 0) {
    return;
  }

  const auto state_version = context->document->StateVersion();
  const auto timer_version = context->mode == ViewMode::Presenter
    ? context->document->PresentationSeconds()
    : 0;

  if (context->texture &&
      context->rendered_state_version == state_version &&
      context->rendered_timer_second == timer_version) {
    return;
  }

  bool ok = false;
  if (context->mode == ViewMode::Presenter) {
    ok = context->document->RenderPresenterBGRA(
      context->width,
      context->height,
      context->pixels,
      context->stride);
  } else {
    ok = context->document->RenderSlideBGRA(
      context->width,
      context->height,
      context->pixels,
      context->stride);
  }
  if (!ok || context->pixels.empty()) {
    return;
  }

  if (!context->texture) {
    const uint8_t *planes[] = { context->pixels.data() };
    context->texture = gs_texture_create(
      context->width,
      context->height,
      GS_BGRA,
      1,
      planes,
      GS_DYNAMIC);
  } else {
    gs_texture_set_image(context->texture, context->pixels.data(), context->stride, false);
  }

  context->rendered_state_version = state_version;
  context->rendered_timer_second = timer_version;
}

bool with_active_document(SourceContext *context, const std::function<void(PresentationDocument &)> &callback)
{
  if (!context || !context->document) {
    return false;
  }

  Registry::Instance().SetActive(context->document);
  callback(*context->document);
  return false;
}

bool control_previous(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.Previous();
  });
}

bool control_next(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.Next();
  });
}

bool control_first(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.First();
  });
}

bool control_last(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.Last();
  });
}

bool control_black(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.ToggleBlackScreen();
  });
}

bool control_reload(obs_properties_t *, obs_property_t *, void *data)
{
  return with_active_document(static_cast<SourceContext *>(data), [](PresentationDocument &document) {
    document.ReloadAsync();
  });
}

}  // namespace

void source_defaults(obs_data_t *settings)
{
  obs_data_set_default_string(settings, "pptx_path", "");
  obs_data_set_default_int(settings, "canvas_width", 1920);
  obs_data_set_default_int(settings, "canvas_height", 1080);
}

obs_properties_t *source_properties(SourceContext *context)
{
  obs_properties_t *props = obs_properties_create_param(context, nullptr);
  obs_properties_add_path(
    props,
    "pptx_path",
    "PowerPoint File (.pptx)",
    OBS_PATH_FILE,
    "PowerPoint (*.pptx)",
    nullptr);
  obs_properties_add_int(props, "canvas_width", "Canvas Width", 320, 7680, 1);
  obs_properties_add_int(props, "canvas_height", "Canvas Height", 240, 4320, 1);

  obs_property_t *help = obs_properties_add_text(props, "pptbridge_help", kHotkeyHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(help, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(help, true);

  obs_properties_add_button(props, "pptbridge_prev_btn", "Previous Slide", control_previous);
  obs_properties_add_button(props, "pptbridge_next_btn", "Next Slide", control_next);
  obs_properties_add_button(props, "pptbridge_first_btn", "First Slide", control_first);
  obs_properties_add_button(props, "pptbridge_last_btn", "Last Slide", control_last);
  obs_properties_add_button(props, "pptbridge_black_btn", "Toggle Black Screen", control_black);
  obs_properties_add_button(props, "pptbridge_reload_btn", "Reload Presentation", control_reload);
  return props;
}

void source_update(SourceContext *context, obs_data_t *settings)
{
  if (!context) {
    return;
  }

  const char *path = obs_data_get_string(settings, "pptx_path");
  const uint32_t width = static_cast<uint32_t>(obs_data_get_int(settings, "canvas_width"));
  const uint32_t height = static_cast<uint32_t>(obs_data_get_int(settings, "canvas_height"));

  const bool path_changed = context->pptx_path != (path ? path : "");
  const bool size_changed = context->width != width || context->height != height;

  context->pptx_path = path ? path : "";
  context->width = width;
  context->height = height;

  if (path_changed) {
    context->document = Registry::Instance().Acquire(context->pptx_path);
    if (context->document) {
      context->document->EnsureLoadingAsync();
      Registry::Instance().SetActive(context->document);
    }
  }

  if (path_changed || size_changed) {
    source_destroy_texture(context);
  }

  context->rendered_state_version = 0;
  context->rendered_timer_second = 0;
}

void source_tick(SourceContext *context)
{
  if (context && context->document) {
    context->document->EnsureLoadingAsync();
  }
}

void source_destroy_texture(SourceContext *context)
{
  if (!context || !context->texture) {
    return;
  }

  obs_enter_graphics();
  gs_texture_destroy(context->texture);
  obs_leave_graphics();
  context->texture = nullptr;
}

void source_render(SourceContext *context, gs_effect_t *effect)
{
  if (!context) {
    return;
  }

  refresh_texture_if_needed(context);
  if (!context->texture) {
    return;
  }

  if (!effect) {
    effect = obs_get_base_effect(OBS_EFFECT_DEFAULT);
  }

  gs_eparam_t *image = gs_effect_get_param_by_name(effect, "image");
  gs_effect_set_texture(image, context->texture);
  while (gs_effect_loop(effect, "Draw")) {
    gs_draw_sprite(context->texture, 0, context->width, context->height);
  }
}

uint32_t source_width(const SourceContext *context)
{
  return context ? context->width : 1920;
}

uint32_t source_height(const SourceContext *context)
{
  return context ? context->height : 1080;
}

static const char *slide_source_get_name(void *)
{
  return "PPTBridge SK Slide";
}

static void *slide_source_create(obs_data_t *settings, obs_source_t *source)
{
  auto *context = new SourceContext();
  context->source = source;
  context->mode = ViewMode::Slide;
  source_update(context, settings);
  return context;
}

static void slide_source_destroy(void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context) {
    return;
  }
  source_destroy_texture(context);
  delete context;
}

static obs_properties_t *slide_source_get_properties(void *data)
{
  return source_properties(static_cast<SourceContext *>(data));
}

static void slide_source_update(void *data, obs_data_t *settings)
{
  source_update(static_cast<SourceContext *>(data), settings);
}

static void slide_source_defaults(obs_data_t *settings)
{
  source_defaults(settings);
}

static void slide_source_video_tick(void *data, float)
{
  source_tick(static_cast<SourceContext *>(data));
}

static void slide_source_video_render(void *data, gs_effect_t *effect)
{
  source_render(static_cast<SourceContext *>(data), effect);
}

static uint32_t slide_source_get_width(void *data)
{
  return source_width(static_cast<SourceContext *>(data));
}

static uint32_t slide_source_get_height(void *data)
{
  return source_height(static_cast<SourceContext *>(data));
}

obs_source_info *pptbridge_slide_source_info()
{
  static obs_source_info info = {};
  info.id = "pptbridge_slide_source";
  info.type = OBS_SOURCE_TYPE_INPUT;
  info.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_CUSTOM_DRAW;
  info.get_name = slide_source_get_name;
  info.create = slide_source_create;
  info.destroy = slide_source_destroy;
  info.get_defaults = slide_source_defaults;
  info.get_properties = slide_source_get_properties;
  info.update = slide_source_update;
  info.video_tick = slide_source_video_tick;
  info.video_render = slide_source_video_render;
  info.get_width = slide_source_get_width;
  info.get_height = slide_source_get_height;
  return &info;
}

}  // namespace pptbridge
