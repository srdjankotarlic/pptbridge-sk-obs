#pragma once

#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <obs-module.h>

#include "presentation_document.hpp"

namespace pptbridge {

enum class ViewMode {
  Slide,
  Presenter,
};

enum class LiveCaptureResizeMode {
  LockCanvas,
  FitWindow,
};

struct SourceContext {
  struct MediaPlayback {
    std::string signature;
    std::string file_path;
    bool is_video = false;
    bool is_audio = false;
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
    obs_source_t *source = nullptr;
    bool showing_child = false;
    bool active_child = false;
  };

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
  PresenterRenderOptions presenter_options;
  bool use_live_powerpoint = true;
  bool auto_start_live_powerpoint = false;
  bool close_live_powerpoint_on_shutdown = true;
  LiveCaptureResizeMode live_capture_resize_mode = LiveCaptureResizeMode::LockCanvas;
  bool audio_enabled = true;
  bool use_live_app_audio = true;
  bool auto_recover_live = true;
  double audio_gain_db = 0.0;
  obs_source_t *live_capture_source = nullptr;
  uint64_t live_capture_window_id = 0;
  std::string live_capture_window_title;
  bool live_capture_hooked = false;
  bool live_capture_showing = false;
  bool live_capture_active = false;
  obs_source_t *live_audio_source = nullptr;
  int live_audio_owner_pid = 0;
  std::string live_audio_application;
  bool live_audio_hooked = false;
  bool live_audio_showing = false;
  bool live_audio_active = false;
  std::chrono::steady_clock::time_point last_live_sync_request = std::chrono::steady_clock::time_point::min();
  std::chrono::steady_clock::time_point live_capture_last_seen = std::chrono::steady_clock::now();
  std::chrono::steady_clock::time_point live_audio_last_seen = std::chrono::steady_clock::now();
  std::chrono::steady_clock::time_point live_recover_last_attempt = std::chrono::steady_clock::time_point::min();
  std::chrono::steady_clock::time_point live_reload_last_attempt = std::chrono::steady_clock::time_point::min();
  std::mutex media_mutex;
  std::string media_signature;
  std::vector<MediaPlayback> media_playback;
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
