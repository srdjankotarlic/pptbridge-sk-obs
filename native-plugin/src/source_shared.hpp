#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <obs-module.h>

#include "presentation_document.hpp"

namespace pptbridge {

enum class ViewMode {
  Slide,
  Presenter,
};

struct SourceContext {
  obs_source_t *source = nullptr;
  std::shared_ptr<PresentationDocument> document;
  ViewMode mode = ViewMode::Slide;
  std::string pptx_path;
  uint32_t width = 1920;
  uint32_t height = 1080;
  gs_texture_t *texture = nullptr;
  std::vector<uint8_t> pixels;
  uint32_t stride = 0;
  uint64_t rendered_state_version = 0;
  uint64_t rendered_timer_second = 0;
};

void source_defaults(obs_data_t *settings);
obs_properties_t *source_properties(SourceContext *context);
void source_update(SourceContext *context, obs_data_t *settings);
void source_tick(SourceContext *context);
void source_destroy_texture(SourceContext *context);
void source_render(SourceContext *context, gs_effect_t *effect);
uint32_t source_width(const SourceContext *context);
uint32_t source_height(const SourceContext *context);

}  // namespace pptbridge
