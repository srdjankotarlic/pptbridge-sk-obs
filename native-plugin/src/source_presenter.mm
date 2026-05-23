#import "source_shared.hpp"

#include "pptbridge_registry.hpp"

namespace pptbridge {

obs_source_info *pptbridge_presenter_source_info()
{
  static const auto get_name = [](void *) -> const char * {
    return "PPTBridge SK Presenter";
  };

  static const auto create = [](obs_data_t *settings, obs_source_t *source) -> void * {
    auto *context = new SourceContext();
    context->source = source;
    context->mode = ViewMode::Presenter;
    source_update(context, settings);
    return context;
  };

  static const auto destroy = [](void *data) {
    auto *context = static_cast<SourceContext *>(data);
    if (!context) {
      return;
    }
    source_destroy(context);
    delete context;
  };

  static const auto get_properties = [](void *data) -> obs_properties_t * {
    return source_properties(static_cast<SourceContext *>(data));
  };

  static const auto update = [](void *data, obs_data_t *settings) {
    source_update(static_cast<SourceContext *>(data), settings);
  };

  static const auto defaults = [](obs_data_t *settings) {
    source_defaults(settings);
  };

  static const auto video_tick = [](void *data, float) {
    source_tick(static_cast<SourceContext *>(data));
  };

  static const auto video_render = [](void *data, gs_effect_t *effect) {
    source_render(static_cast<SourceContext *>(data), effect);
  };

  static const auto activate = [](void *data) {
    auto *context = static_cast<SourceContext *>(data);
    if (context && context->document) {
      Registry::Instance().SetActive(context->document);
    }
  };

  static const auto get_width = [](void *data) -> uint32_t {
    return source_width(static_cast<SourceContext *>(data));
  };

  static const auto get_height = [](void *data) -> uint32_t {
    return source_height(static_cast<SourceContext *>(data));
  };

  static obs_source_info info = {};
  info.id = "pptbridge_presenter_source";
  info.type = OBS_SOURCE_TYPE_INPUT;
  info.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_CUSTOM_DRAW;
  info.get_name = get_name;
  info.create = create;
  info.destroy = destroy;
  info.get_defaults = defaults;
  info.get_properties = get_properties;
  info.update = update;
  info.activate = activate;
  info.video_tick = video_tick;
  info.video_render = video_render;
  info.get_width = get_width;
  info.get_height = get_height;
  return &info;
}

}  // namespace pptbridge
