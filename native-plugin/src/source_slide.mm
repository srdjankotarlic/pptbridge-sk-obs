#import "source_shared.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <functional>
#include <sstream>
#include <obs-frontend-api.h>
#include <util/platform.h>

#include "pptbridge_osc_server.hpp"
#include "pptbridge_registry.hpp"

namespace pptbridge {

namespace {

constexpr const char *kHotkeyHelp =
  "Slide control (PPTX or PDF):\n"
  "1. Built-in defaults while OBS is focused: 2 = next slide,\n"
  "   1 = previous slide. Normal left/right arrows stay free.\n"
  "2. PPTBridge only acts on hotkeys while OBS is the active app, so typing\n"
  "   in another window will not accidentally move the presentation.\n"
  "3. Open OBS Settings > Hotkeys if you want to change the keys or bind a\n"
  "   clicker button. Use PPTBridge SK: Next Slide / Previous Slide, and add\n"
  "   PageDown/PageUp there if those keys only need to work while OBS is focused.\n"
  "4. For a stage clicker while you use Chrome, OBS, or another app, enable\n"
  "   Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off. It captures\n"
  "   PageDown and PageUp globally, sends them to the current\n"
  "   program scene deck, and keeps plain typing keys such as Space available.\n"
  "   This works for PPTX live mode and for PDF/cached decks without live mode.\n"
  "5. If you brought a PDF presentation instead of a PPTX, pick the .pdf in\n"
  "   the file field above - PPTBridge renders pages natively, no PowerPoint\n"
  "   required, and all hotkeys work identically.\n"
  "6. Multi-deck shows: put each presentation in its own scene. The hotkey\n"
  "   router automatically targets the PPTBridge source in the current\n"
  "   program scene, so Spotlight on stage always drives the right deck.\n"
  "7. Use the buttons below for quick testing inside OBS.";

constexpr const char *kMediaHelp =
  "Media note:\n"
  "In True Live PowerPoint Mode, PowerPoint itself drives builds, animations, video, and slide timing.\n"
  "If live mode is unavailable or disabled, PPTBridge falls back to legacy render mode with best-effort embedded media playback through OBS.";

constexpr const char *kLiveHelp =
  "True live mode:\n"
  "PowerPoint itself runs the slideshow, so click-build animations, embedded video, and slide timing behave like real PowerPoint.\n"
  "Recommended for macOS when Microsoft PowerPoint is installed.\n"
  "PowerPoint can either start automatically with OBS or wait until you click Start / Restart PowerPoint Live Mode in the highlighted control group above.";

constexpr const char *kLiveControlHelp =
  "Main PowerPoint live controls:\n"
  "Start / Restart opens PowerPoint if needed, begins the live slideshow, and recovers the deck if the slideshow window was closed.\n"
  "Stop ends the PowerPoint live slideshow without quitting OBS.";

constexpr const char *kLiveResizeHelp =
  "PowerPoint window resize:\n"
  "Lock OBS Output Size keeps the PPTBridge source filling the OBS canvas even if you shrink or resize the PowerPoint slideshow window.\n"
  "Use Follow PowerPoint Window only when you intentionally want the OBS output to reflect the current PowerPoint window shape.";

constexpr const char *kAudioHelp =
  "Conference audio:\n"
  "Audio from the PowerPoint slideshow is routed into the PPTBridge SK Slide source when available.\n"
  "OBS controls this audio in the Audio Mixer, not inside the video frame.\n"
  "In Studio Mode, the PPTBridge source currently active in Program is the one that should drive audio.\n"
  "For the cleanest live workflow, reuse one existing PPTBridge SK Slide source across scenes instead of making multiple copies of the same deck.";

constexpr auto kLiveRecoverRetryDelay = std::chrono::seconds(3);
constexpr auto kLiveReloadDelay = std::chrono::seconds(10);

PresenterLayoutPreset presenter_layout_from_setting(const char *value)
{
  const std::string setting = value ? value : "";
  if (setting == "large_preview") {
    return PresenterLayoutPreset::LargePreview;
  }
  if (setting == "large_notes") {
    return PresenterLayoutPreset::LargeNotes;
  }
  if (setting == "compact") {
    return PresenterLayoutPreset::Compact;
  }
  if (setting == "confidence_monitor") {
    return PresenterLayoutPreset::ConfidenceMonitor;
  }
  return PresenterLayoutPreset::Balanced;
}

PresenterPreviewScaleMode presenter_preview_scale_from_setting(const char *value)
{
  const std::string setting = value ? value : "";
  if (setting == "fill") {
    return PresenterPreviewScaleMode::Fill;
  }
  if (setting == "crop") {
    return PresenterPreviewScaleMode::Crop;
  }
  return PresenterPreviewScaleMode::Fit;
}

PresenterBackgroundImageMode presenter_background_image_mode_from_setting(const char *value)
{
  const std::string setting = value ? value : "";
  if (setting == "fill") {
    return PresenterBackgroundImageMode::Fill;
  }
  if (setting == "fit") {
    return PresenterBackgroundImageMode::Fit;
  }
  return PresenterBackgroundImageMode::Watermark;
}

LiveCaptureResizeMode live_capture_resize_mode_from_setting(const char *value)
{
  const std::string setting = value ? value : "";
  if (setting == "fit_window") {
    return LiveCaptureResizeMode::FitWindow;
  }
  return LiveCaptureResizeMode::LockCanvas;
}

const char *live_capture_resize_mode_to_setting(LiveCaptureResizeMode mode)
{
  return mode == LiveCaptureResizeMode::FitWindow ? "fit_window" : "lock_canvas";
}

double clamp_setting(double value, double minimum, double maximum, double fallback)
{
  if (value < minimum || value > maximum) {
    value = value <= 0.0 ? fallback : value;
  }
  return std::clamp(value, minimum, maximum);
}

PresenterRenderOptions presenter_options_from_settings(obs_data_t *settings)
{
  PresenterRenderOptions options;
  if (!settings) {
    return options;
  }

  options.layout = presenter_layout_from_setting(obs_data_get_string(settings, "presenter_layout"));
  options.preview_scale_mode =
    presenter_preview_scale_from_setting(obs_data_get_string(settings, "presenter_preview_scale_mode"));
  options.background_image_mode =
    presenter_background_image_mode_from_setting(obs_data_get_string(settings, "presenter_background_image_mode"));
  options.preview_scale_percent =
    clamp_setting(obs_data_get_double(settings, "presenter_preview_scale_percent"), 25.0, 300.0, 100.0);
  options.preview_position_x =
    clamp_setting(obs_data_get_double(settings, "presenter_preview_position_x"), -100.0, 100.0, 0.0);
  options.preview_position_y =
    clamp_setting(obs_data_get_double(settings, "presenter_preview_position_y"), -100.0, 100.0, 0.0);
  options.side_panel_width_percent =
    clamp_setting(obs_data_get_double(settings, "presenter_side_panel_width_percent"), 50.0, 220.0, 100.0);
  options.notes_font_size =
    clamp_setting(obs_data_get_double(settings, "presenter_notes_font_size"), 10.0, 42.0, 16.0);
  options.notes_area_percent =
    clamp_setting(obs_data_get_double(settings, "presenter_notes_area_percent"), 60.0, 180.0, 100.0);
  options.notes_zoom_percent =
    clamp_setting(obs_data_get_double(settings, "presenter_notes_zoom_percent"), 50.0, 200.0, 100.0);
  options.notes_position_y =
    clamp_setting(obs_data_get_double(settings, "presenter_notes_position_y"), -100.0, 100.0, 0.0);
  options.background_color = static_cast<uint32_t>(obs_data_get_int(settings, "presenter_background_color"));
  const char *background_image_path = obs_data_get_string(settings, "presenter_background_image_path");
  options.background_image_path = background_image_path ? background_image_path : "";
  options.background_image_opacity_percent =
    clamp_setting(obs_data_get_double(settings, "presenter_background_image_opacity_percent"), 0.0, 100.0, 22.0);
  options.show_cue_list = obs_data_get_bool(settings, "presenter_show_cue_list");
  return options;
}

bool visual_child_sources_wanted(const SourceContext *context)
{
  return context && context->mode == ViewMode::Slide;
}

bool presenter_options_equal(const PresenterRenderOptions &left, const PresenterRenderOptions &right)
{
  return left.layout == right.layout &&
         left.preview_scale_mode == right.preview_scale_mode &&
         left.preview_scale_percent == right.preview_scale_percent &&
         left.preview_position_x == right.preview_position_x &&
         left.preview_position_y == right.preview_position_y &&
         left.side_panel_width_percent == right.side_panel_width_percent &&
         left.notes_font_size == right.notes_font_size &&
         left.notes_area_percent == right.notes_area_percent &&
         left.notes_zoom_percent == right.notes_zoom_percent &&
         left.notes_position_y == right.notes_position_y &&
         left.background_color == right.background_color &&
         left.background_image_path == right.background_image_path &&
         left.background_image_mode == right.background_image_mode &&
         left.background_image_opacity_percent == right.background_image_opacity_percent &&
         left.show_cue_list == right.show_cue_list;
}

void add_presenter_customization_properties(obs_properties_t *props)
{
  obs_property_t *layout = obs_properties_add_list(
    props,
    "presenter_layout",
    "Presenter Layout",
    OBS_COMBO_TYPE_LIST,
    OBS_COMBO_FORMAT_STRING);
  obs_property_list_add_string(layout, "Balanced", "balanced");
  obs_property_list_add_string(layout, "Large Preview", "large_preview");
  obs_property_list_add_string(layout, "Large Notes", "large_notes");
  obs_property_list_add_string(layout, "Compact", "compact");
  obs_property_list_add_string(layout, "Confidence Monitor", "confidence_monitor");

  obs_property_t *scale_mode = obs_properties_add_list(
    props,
    "presenter_preview_scale_mode",
    "Preview Scale Mode",
    OBS_COMBO_TYPE_LIST,
    OBS_COMBO_FORMAT_STRING);
  obs_property_list_add_string(scale_mode, "Fit", "fit");
  obs_property_list_add_string(scale_mode, "Fill", "fill");
  obs_property_list_add_string(scale_mode, "Crop", "crop");

  obs_properties_add_float_slider(props, "presenter_preview_scale_percent", "Preview Scale (%)", 25.0, 300.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_preview_position_x", "Preview Position X", -100.0, 100.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_preview_position_y", "Preview Position Y", -100.0, 100.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_side_panel_width_percent", "Right Panel Width (%)", 50.0, 220.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_notes_font_size", "Notes Font Size", 10.0, 42.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_notes_area_percent", "Notes / Next Slide Split (%)", 60.0, 180.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_notes_zoom_percent", "Notes Zoom (%)", 50.0, 200.0, 1.0);
  obs_properties_add_float_slider(props, "presenter_notes_position_y", "Notes Text Position Y", -100.0, 100.0, 1.0);
  obs_properties_add_color(props, "presenter_background_color", "Presenter Background Color");
  obs_properties_add_path(
    props,
    "presenter_background_image_path",
    "Presenter Background Image / Logo",
    OBS_PATH_FILE,
    "Images (*.png *.jpg *.jpeg *.webp *.tif *.tiff);;All files (*.*)",
    nullptr);
  obs_property_t *background_mode = obs_properties_add_list(
    props,
    "presenter_background_image_mode",
    "Background Image Placement",
    OBS_COMBO_TYPE_LIST,
    OBS_COMBO_FORMAT_STRING);
  obs_property_list_add_string(background_mode, "Watermark / Logo", "watermark");
  obs_property_list_add_string(background_mode, "Fit Center", "fit");
  obs_property_list_add_string(background_mode, "Fill Background", "fill");
  obs_properties_add_float_slider(
    props,
    "presenter_background_image_opacity_percent",
    "Background Image Opacity (%)",
    0.0,
    100.0,
    1.0);
  obs_properties_add_bool(props, "presenter_show_cue_list", "Show Cue List In Presenter View");
}

struct MediaPlaybackSnapshot {
  obs_source_t *source = nullptr;
  bool is_video = false;
  bool is_audio = false;
  float x = 0.0f;
  float y = 0.0f;
  float width = 0.0f;
  float height = 0.0f;
};

struct ChildAudioSnapshot {
  obs_source_t *source = nullptr;
  bool is_audio = false;
};

struct LiveCaptureSnapshot {
  obs_source_t *source = nullptr;
  uint64_t window_id = 0;
  std::string window_title;
  bool active = false;
};

struct LiveAudioSnapshot {
  obs_source_t *source = nullptr;
  int owner_pid = 0;
  std::string application;
  bool active = false;
};

struct LiveChildStatus {
  bool capture_present = false;
  uint64_t capture_window_id = 0;
  std::string capture_window_title;
  bool audio_present = false;
  std::string audio_application;
};

struct LiveAudioTarget {
  std::string bundle_id;
  std::string application_name;
  int pid = 0;
};

float audio_gain_multiplier_db(double gain_db);
void forward_child_audio_for_meter(
  void *param,
  obs_source_t *source,
  const struct audio_data *audio_data,
  bool muted);

std::string ToStdStringLocal(NSString *value)
{
  return value ? std::string(value.UTF8String) : std::string();
}

std::string build_media_signature(const std::vector<EmbeddedMedia> &media_items)
{
  std::ostringstream stream;
  stream << media_items.size();
  for (const auto &media : media_items) {
    stream << "|"
           << static_cast<int>(media.kind) << ":"
           << media.file_path << ":"
           << media.x << ":"
           << media.y << ":"
           << media.width << ":"
           << media.height;
  }
  return stream.str();
}

LiveCaptureSnapshot snapshot_live_capture(const SourceContext *context)
{
  LiveCaptureSnapshot snapshot;
  if (!context) {
    return snapshot;
  }

  std::lock_guard<std::mutex> lock(context->live_sources_mutex);
  if (context->live_capture_source) {
    snapshot.source = obs_source_get_ref(context->live_capture_source);
  }
  snapshot.window_id = context->live_capture_window_id;
  snapshot.window_title = context->live_capture_window_title;
  snapshot.active = context->live_capture_active;
  return snapshot;
}

void release_live_capture_snapshot(LiveCaptureSnapshot &snapshot)
{
  if (snapshot.source) {
    obs_source_release(snapshot.source);
    snapshot.source = nullptr;
  }
}

LiveAudioSnapshot snapshot_live_audio(const SourceContext *context)
{
  LiveAudioSnapshot snapshot;
  if (!context) {
    return snapshot;
  }

  std::lock_guard<std::mutex> lock(context->live_sources_mutex);
  if (context->live_audio_source) {
    snapshot.source = obs_source_get_ref(context->live_audio_source);
  }
  snapshot.owner_pid = context->live_audio_owner_pid;
  snapshot.application = context->live_audio_application;
  snapshot.active = context->live_audio_active;
  return snapshot;
}

void release_live_audio_snapshot(LiveAudioSnapshot &snapshot)
{
  if (snapshot.source) {
    obs_source_release(snapshot.source);
    snapshot.source = nullptr;
  }
}

LiveChildStatus snapshot_live_child_status(const SourceContext *context)
{
  LiveChildStatus status;
  if (!context) {
    return status;
  }

  std::lock_guard<std::mutex> lock(context->live_sources_mutex);
  status.capture_present = context->live_capture_source != nullptr;
  status.capture_window_id = context->live_capture_window_id;
  status.capture_window_title = context->live_capture_window_title;
  status.audio_present = context->live_audio_source != nullptr;
  status.audio_application = context->live_audio_application;
  return status;
}

void start_media_playback(obs_source_t *source)
{
  if (!source) {
    return;
  }

  obs_source_media_stop(source);
  obs_source_media_restart(source);
}

void set_media_playback_active(
  SourceContext *context,
  SourceContext::MediaPlayback &media,
  bool should_be_showing,
  bool should_be_active)
{
  if (!context || !context->source || !media.source) {
    return;
  }

  bool started = false;

  if (should_be_showing && !media.showing_child) {
    obs_source_inc_showing(media.source);
    media.showing_child = true;
    started = true;
  }

  if (should_be_active && !media.active_child) {
    if (obs_source_add_active_child(context->source, media.source)) {
      media.active_child = true;
      started = true;
    }
  }

  if (started) {
    start_media_playback(media.source);
  }

  if (!should_be_active && media.active_child) {
    obs_source_remove_active_child(context->source, media.source);
    media.active_child = false;
  }

  if (!should_be_showing && media.showing_child) {
    obs_source_media_stop(media.source);
    obs_source_dec_showing(media.source);
    media.showing_child = false;
  }
}

void clear_media_sources(SourceContext *context)
{
  if (!context) {
    return;
  }

  std::vector<SourceContext::MediaPlayback> stale;
  {
    std::lock_guard<std::mutex> lock(context->media_mutex);
    stale.swap(context->media_playback);
  }

  for (auto &media : stale) {
    set_media_playback_active(context, media, false, false);
    if (media.source) {
      if (media.audio_capture_registered) {
        obs_source_remove_audio_capture_callback(media.source, forward_child_audio_for_meter, context);
        media.audio_capture_registered = false;
      }
      obs_source_release(media.source);
      media.source = nullptr;
    }
  }
}

void sync_media_playback_activity(SourceContext *context)
{
  if (!visual_child_sources_wanted(context)) {
    return;
  }

  const bool should_be_active = context->source && obs_source_active(context->source);
  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || should_be_active);
  std::lock_guard<std::mutex> lock(context->media_mutex);
  for (auto &media : context->media_playback) {
    set_media_playback_active(context, media, should_be_showing, should_be_active);
  }
}

std::vector<MediaPlaybackSnapshot> snapshot_media_playback(SourceContext *context)
{
  std::vector<MediaPlaybackSnapshot> snapshot;
  if (!context) {
    return snapshot;
  }

  std::lock_guard<std::mutex> lock(context->media_mutex);
  snapshot.reserve(context->media_playback.size());
  for (const auto &media : context->media_playback) {
    if (!media.source) {
      continue;
    }

    MediaPlaybackSnapshot item;
    item.source = obs_source_get_ref(media.source);
    item.is_video = media.is_video;
    item.is_audio = media.is_audio;
    item.x = media.x;
    item.y = media.y;
    item.width = media.width;
    item.height = media.height;
    if (item.source) {
      snapshot.push_back(item);
    }
  }

  return snapshot;
}

void release_media_playback_snapshot(std::vector<MediaPlaybackSnapshot> &snapshot)
{
  for (auto &media : snapshot) {
    if (media.source) {
      obs_source_release(media.source);
      media.source = nullptr;
    }
  }
}

CGWindowID find_powerpoint_window_id(const std::string &window_title, const std::string &deck_name)
{
  if (window_title.empty() && deck_name.empty()) {
    return kCGNullWindowID;
  }

  NSArray *windows =
    (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
  if (!windows) {
    return kCGNullWindowID;
  }

  NSString *target_title = window_title.empty() ? nil : [NSString stringWithUTF8String:window_title.c_str()];
  NSString *deck_name_ns = deck_name.empty() ? nil : [NSString stringWithUTF8String:deck_name.c_str()];
  NSString *deck_stem = deck_name_ns ? [[deck_name_ns lastPathComponent] stringByDeletingPathExtension] : nil;

  CGWindowID matched_id = kCGNullWindowID;
  CGWindowID deck_fallback_id = kCGNullWindowID;
  CGWindowID only_slideshow_id = kCGNullWindowID;
  std::size_t slideshow_count = 0;
  for (NSDictionary *window in windows) {
    NSString *owner_name = [window objectForKey:(NSString *)kCGWindowOwnerName];
    NSString *name = [window objectForKey:(NSString *)kCGWindowName];
    NSNumber *window_id = [window objectForKey:(NSString *)kCGWindowNumber];

    if (!owner_name || !name || !window_id) {
      continue;
    }

    const std::string title = name.UTF8String ? name.UTF8String : "";
    if (![owner_name localizedCaseInsensitiveContainsString:@"PowerPoint"]) {
      continue;
    }

    if (target_title && [name isEqualToString:target_title]) {
      matched_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
      break;
    }

    const bool is_slideshow_window =
      [name localizedCaseInsensitiveContainsString:@"PowerPoint Slide Show"] ||
      [name localizedCaseInsensitiveContainsString:@"Slide Show"];

    if (is_slideshow_window) {
      slideshow_count += 1;
      only_slideshow_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
    }

    if (deck_stem && is_slideshow_window && [name localizedCaseInsensitiveContainsString:deck_stem]) {
      deck_fallback_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
    }
  }

  if (matched_id != kCGNullWindowID) {
    return matched_id;
  }
  if (deck_fallback_id != kCGNullWindowID) {
    return deck_fallback_id;
  }

  // A generic slideshow fallback is safe only when there is no second deck
  // that it could accidentally attach to in a multi-presentation show.
  return slideshow_count == 1 ? only_slideshow_id : kCGNullWindowID;
}

void set_live_capture_active_locked(SourceContext *context, bool should_be_showing, bool should_be_active)
{
  if (!context || !context->source || !context->live_capture_source) {
    return;
  }

  if (should_be_showing && !context->live_capture_showing) {
    obs_source_inc_showing(context->live_capture_source);
    context->live_capture_showing = true;
  }

  if (should_be_active && !context->live_capture_active) {
    if (obs_source_add_active_child(context->source, context->live_capture_source)) {
      context->live_capture_active = true;
    }
  }

  if (!should_be_active && context->live_capture_active) {
    obs_source_remove_active_child(context->source, context->live_capture_source);
    context->live_capture_active = false;
  }

  if (!should_be_showing && context->live_capture_showing) {
    obs_source_dec_showing(context->live_capture_source);
    context->live_capture_showing = false;
  }
}

void set_live_capture_active(SourceContext *context, bool should_be_showing, bool should_be_active)
{
  if (!context) {
    return;
  }

  std::lock_guard<std::mutex> lock(context->live_sources_mutex);
  set_live_capture_active_locked(context, should_be_showing, should_be_active);
}

void set_live_audio_active_locked(SourceContext *context, bool should_be_showing, bool should_be_active)
{
  if (!context || !context->source || !context->live_audio_source) {
    return;
  }

  if (should_be_showing && !context->live_audio_showing) {
    obs_source_inc_showing(context->live_audio_source);
    context->live_audio_showing = true;
  }

  if (should_be_active && !context->live_audio_active) {
    if (obs_source_add_active_child(context->source, context->live_audio_source)) {
      context->live_audio_active = true;
    }
  }

  if (!should_be_active && context->live_audio_active) {
    obs_source_remove_active_child(context->source, context->live_audio_source);
    context->live_audio_active = false;
  }

  if (!should_be_showing && context->live_audio_showing) {
    obs_source_dec_showing(context->live_audio_source);
    context->live_audio_showing = false;
  }
}

void set_live_audio_active(SourceContext *context, bool should_be_showing, bool should_be_active)
{
  if (!context) {
    return;
  }

  std::lock_guard<std::mutex> lock(context->live_sources_mutex);
  set_live_audio_active_locked(context, should_be_showing, should_be_active);
}

void release_live_capture_source(SourceContext *context)
{
  if (!context) {
    return;
  }

  obs_source_t *stale_source = nullptr;
  {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    set_live_capture_active_locked(context, false, false);
    stale_source = context->live_capture_source;
    context->live_capture_source = nullptr;
    context->live_capture_window_id = 0;
    context->live_capture_window_title.clear();
    context->live_capture_hooked = false;
  }

  if (stale_source) {
    obs_source_release(stale_source);
  }
}

bool live_capture_is_renderable(SourceContext *context)
{
  auto snapshot = snapshot_live_capture(context);
  const bool renderable = snapshot.source &&
                          snapshot.window_id != 0 &&
                          obs_source_get_width(snapshot.source) > 0 &&
                          obs_source_get_height(snapshot.source) > 0;
  release_live_capture_snapshot(snapshot);
  return renderable;
}

void clear_live_audio_source(SourceContext *context)
{
  if (!context) {
    return;
  }

  obs_source_t *stale_source = nullptr;
  bool remove_audio_callback = false;
  {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    set_live_audio_active_locked(context, false, false);
    stale_source = context->live_audio_source;
    remove_audio_callback = context->live_audio_capture_registered;
    context->live_audio_source = nullptr;
    context->live_audio_capture_registered = false;
    context->live_audio_owner_pid = 0;
    context->live_audio_application.clear();
    context->live_audio_hooked = false;
  }

  if (stale_source) {
    if (remove_audio_callback) {
      obs_source_remove_audio_capture_callback(
        stale_source,
        forward_child_audio_for_meter,
        context);
    }
    obs_source_release(stale_source);
  }
}

obs_source_t *create_live_capture_source(SourceContext *context, uint32_t window_id, const std::string &window_title)
{
  if (!context || !context->source || window_id == 0) {
    return nullptr;
  }

  obs_data_t *settings = obs_data_create();
  obs_data_set_int(settings, "type", 1);
  obs_data_set_int(settings, "window", window_id);
  obs_data_set_string(settings, "window_name", window_title.c_str());
  obs_data_set_string(settings, "owner_name", "Microsoft PowerPoint");
  obs_data_set_bool(settings, "show_cursor", false);
  obs_data_set_bool(settings, "show_hidden_windows", true);
  obs_data_set_bool(settings, "show_empty_names", true);

  std::string source_name = std::string(obs_source_get_name(context->source)) + " Live Capture";
  obs_source_t *capture = obs_source_create_private("screen_capture", source_name.c_str(), settings);
  if (!capture) {
    capture = obs_source_create_private("window_capture", source_name.c_str(), settings);
  }
  obs_data_release(settings);

  if (!capture) {
    blog(LOG_WARNING, "[PPTBridge SK] Could not create a live PowerPoint capture source");
    return nullptr;
  }

  // Attach a crop filter that strips PowerPoint's windowed-slideshow
  // title bar ("PowerPoint Slide Show – [Deck Name]") from the top of
  // the capture. macOS window chrome is ~28 points; on a Retina display
  // the window-capture stream comes out at 2x pixel dimensions, so we
  // crop 56 pixels. The crop_filter output shrinks obs_source_get_height
  // accordingly, so the aspect-fit in render_live_capture automatically
  // reflows the remaining slide content to 1920x1080 without bars at
  // the top - the program feed stays clean and title-bar-free even
  // though PowerPoint itself is running in a normal windowed slideshow
  // (which was the requirement so the presenter can still use OBS and
  // the rest of macOS on the main display).
  obs_data_t *crop_settings = obs_data_create();
  obs_data_set_bool(crop_settings, "relative", true);
  obs_data_set_int(crop_settings, "left", 0);
  obs_data_set_int(crop_settings, "right", 0);
  obs_data_set_int(crop_settings, "top", 56);
  obs_data_set_int(crop_settings, "bottom", 0);
  obs_source_t *crop = obs_source_create_private(
    "crop_filter",
    "PPTBridge SK Title Bar Crop",
    crop_settings);
  obs_data_release(crop_settings);
  if (crop) {
    obs_source_filter_add(capture, crop);
    // The filter is retained by the capture source via obs_source_filter_add;
    // release our initial reference so ownership is clean.
    obs_source_release(crop);
  } else {
    blog(LOG_WARNING, "[PPTBridge SK] Could not attach title-bar crop filter; program feed may show window chrome");
  }

  return capture;
}

LiveAudioTarget find_powerpoint_audio_target()
{
  @autoreleasepool {
    NSArray<NSRunningApplication *> *apps =
      [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.microsoft.Powerpoint"];
    for (NSRunningApplication *app in apps) {
      if (!app || app.terminated) {
        continue;
      }

      LiveAudioTarget target;
      target.bundle_id = "com.microsoft.Powerpoint";
      target.application_name = app.localizedName ? ToStdStringLocal(app.localizedName) : "Microsoft PowerPoint";
      target.pid = static_cast<int>(app.processIdentifier);
      return target;
    }

    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
      if (!app || app.terminated) {
        continue;
      }

      NSString *localized_name = app.localizedName ?: @"";
      NSString *bundle_identifier = app.bundleIdentifier ?: @"";
      if ([localized_name localizedCaseInsensitiveContainsString:@"PowerPoint"] ||
          [bundle_identifier isEqualToString:@"com.microsoft.Powerpoint"]) {
        LiveAudioTarget target;
        target.bundle_id = bundle_identifier.length > 0 ? ToStdStringLocal(bundle_identifier) : "com.microsoft.Powerpoint";
        target.application_name = localized_name.length > 0 ? ToStdStringLocal(localized_name) : "Microsoft PowerPoint";
        target.pid = static_cast<int>(app.processIdentifier);
        return target;
      }
    }
  }

  return {};
}

obs_source_t *create_live_audio_source(SourceContext *context, const LiveAudioTarget &target)
{
  if (!context || !context->source || target.bundle_id.empty()) {
    return nullptr;
  }

  obs_data_t *settings = obs_data_create();
  obs_data_set_int(settings, "type", 1);
  obs_data_set_string(settings, "application", target.bundle_id.c_str());

  std::string source_name = std::string(obs_source_get_name(context->source)) + " Live Audio";
  obs_source_t *audio = obs_source_create_private("sck_audio_capture", source_name.c_str(), settings);
  obs_data_release(settings);

  if (!audio) {
    blog(
      LOG_WARNING,
      "[PPTBridge SK] Could not create PowerPoint app audio capture source for '%s'",
      target.application_name.c_str());
  }

  return audio;
}

void sync_live_capture_activity(SourceContext *context)
{
  if (!context) {
    return;
  }

  const bool should_be_active = context->source && obs_source_active(context->source);
  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || should_be_active);
  set_live_capture_active(context, should_be_showing, should_be_active);
}

void sync_live_audio_activity(SourceContext *context)
{
  if (!context) {
    return;
  }

  const bool should_be_active = context->source && obs_source_active(context->source);
  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || should_be_active);
  set_live_audio_active(context, should_be_showing, should_be_active);
}

void sync_live_capture_source(SourceContext *context)
{
  if (!context || !visual_child_sources_wanted(context) || !context->document || !context->use_live_powerpoint) {
    release_live_capture_source(context);
    return;
  }

  if (context->live_capture_suppressed_after_stop) {
    if (!context->document->IsLivePowerPointReady()) {
      context->live_capture_suppressed_after_stop = false;
    } else {
      release_live_capture_source(context);
      return;
    }
  }

  if (!context->document->IsLivePowerPointReady()) {
    release_live_capture_source(context);
    return;
  }

  const auto window_title = context->document->LiveWindowTitle();
  const auto window_id = static_cast<uint32_t>(find_powerpoint_window_id(window_title, context->document->Name()));
  auto current_capture = snapshot_live_capture(context);
  if (window_id == 0) {
    const bool keep_current = current_capture.source && current_capture.window_title == window_title;
    release_live_capture_snapshot(current_capture);
    if (keep_current) {
      sync_live_capture_activity(context);
      return;
    }
    release_live_capture_source(context);
    return;
  }

  const bool capture_matches = current_capture.source &&
                               current_capture.window_id == window_id &&
                               current_capture.window_title == window_title;
  release_live_capture_snapshot(current_capture);
  if (capture_matches) {
    sync_live_capture_activity(context);
    return;
  }

  release_live_capture_source(context);
  obs_source_t *capture = create_live_capture_source(context, window_id, window_title);
  if (!capture) {
    return;
  }

  bool installed = false;
  {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    if (!context->live_capture_source) {
      context->live_capture_source = capture;
      context->live_capture_window_id = window_id;
      context->live_capture_window_title = window_title;
      installed = true;
    }
  }
  if (!installed) {
    obs_source_release(capture);
    return;
  }
  blog(
    LOG_INFO,
    "[PPTBridge SK] Attached live PowerPoint capture candidate id=%u title='%s'",
    window_id,
    window_title.c_str());
  sync_live_capture_activity(context);
}

void sync_live_audio_source(SourceContext *context)
{
  if (!context || context->mode != ViewMode::Slide || !context->document || !context->use_live_powerpoint ||
      !context->use_live_app_audio || !context->audio_enabled.load(std::memory_order_relaxed)) {
    clear_live_audio_source(context);
    return;
  }

  if (!context->document->IsLivePowerPointReady()) {
    clear_live_audio_source(context);
    return;
  }

  const auto target = find_powerpoint_audio_target();
  if (target.application_name.empty()) {
    clear_live_audio_source(context);
    return;
  }

  auto current_audio = snapshot_live_audio(context);
  const bool audio_matches = current_audio.source &&
                             current_audio.owner_pid == target.pid &&
                             current_audio.application == target.application_name;
  release_live_audio_snapshot(current_audio);
  if (audio_matches) {
    sync_live_audio_activity(context);
    return;
  }

  clear_live_audio_source(context);
  obs_source_t *audio = create_live_audio_source(context, target);
  if (audio) {
    obs_source_add_audio_capture_callback(
      audio,
      forward_child_audio_for_meter,
      context);
  }

  bool installed = false;
  if (audio) {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    if (!context->live_audio_source) {
      context->live_audio_source = audio;
      context->live_audio_capture_registered = true;
      context->live_audio_owner_pid = target.pid;
      context->live_audio_application = target.application_name;
      installed = true;
    }
  }
  if (audio && !installed) {
    obs_source_remove_audio_capture_callback(audio, forward_child_audio_for_meter, context);
    obs_source_release(audio);
    return;
  }
  sync_live_audio_activity(context);
}

bool render_live_capture(SourceContext *context)
{
  if (!context || !context->document || context->document->IsBlackScreen() ||
      !context->document->IsLivePowerPointReady()) {
    return false;
  }

  auto capture = snapshot_live_capture(context);
  if (!capture.source || capture.window_id == 0) {
    release_live_capture_snapshot(capture);
    return false;
  }

  const uint32_t capture_width = obs_source_get_width(capture.source);
  const uint32_t capture_height = obs_source_get_height(capture.source);
  if (capture_width == 0 || capture_height == 0) {
    release_live_capture_snapshot(capture);
    return false;
  }

  // Default to a locked OBS output: the PowerPoint window may be resized
  // smaller on the desktop, but the PPTBridge source still fills its OBS
  // canvas. The optional fit mode preserves the old behavior for users who
  // intentionally want the program feed to follow the PowerPoint window shape.
  const float canvas_w = static_cast<float>(context->width);
  const float canvas_h = static_cast<float>(context->height);
  const float cap_w = static_cast<float>(capture_width);
  const float cap_h = static_cast<float>(capture_height);
  const float scale = context->live_capture_resize_mode == LiveCaptureResizeMode::FitWindow
    ? std::min(canvas_w / cap_w, canvas_h / cap_h)
    : std::max(canvas_w / cap_w, canvas_h / cap_h);
  const float target_w = cap_w * scale;
  const float target_h = cap_h * scale;
  const float offset_x = (canvas_w - target_w) * 0.5f;
  const float offset_y = (canvas_h - target_h) * 0.5f;

  gs_matrix_push();
  gs_matrix_translate3f(offset_x, offset_y, 0.0f);
  gs_matrix_scale3f(scale, scale, 1.0f);
  obs_source_video_render(capture.source);
  gs_matrix_pop();
  release_live_capture_snapshot(capture);
  return true;
}

std::vector<ChildAudioSnapshot> snapshot_audio_children(SourceContext *context)
{
  std::vector<ChildAudioSnapshot> snapshot;
  if (!context) {
    return snapshot;
  }

  {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    if (context->live_capture_source && context->live_capture_window_id != 0) {
      ChildAudioSnapshot live;
      live.source = obs_source_get_ref(context->live_capture_source);
      live.is_audio = true;
      if (live.source) {
        snapshot.push_back(live);
      }
    }

    if (context->live_audio_source) {
      ChildAudioSnapshot live_audio;
      live_audio.source = obs_source_get_ref(context->live_audio_source);
      live_audio.is_audio = true;
      if (live_audio.source) {
        snapshot.push_back(live_audio);
      }
    }
  }

  std::lock_guard<std::mutex> lock(context->media_mutex);
  for (const auto &media : context->media_playback) {
    if (!media.source || !media.is_audio) {
      continue;
    }

    ChildAudioSnapshot item;
    item.source = obs_source_get_ref(media.source);
    item.is_audio = true;
    if (item.source) {
      snapshot.push_back(item);
    }
  }

  return snapshot;
}

void release_audio_children_snapshot(std::vector<ChildAudioSnapshot> &snapshot)
{
  for (auto &item : snapshot) {
    if (item.source) {
      obs_source_release(item.source);
      item.source = nullptr;
    }
  }
}

SourceContext::MediaPlayback create_media_playback(SourceContext *context, const EmbeddedMedia &media, size_t index)
{
  SourceContext::MediaPlayback playback;
  playback.signature = build_media_signature({ media });
  playback.file_path = media.file_path;
  playback.is_video = media.kind == EmbeddedMediaKind::Video;
  playback.is_audio = context && context->mode == ViewMode::Slide;
  playback.x = static_cast<float>(media.x);
  playback.y = static_cast<float>(media.y);
  playback.width = static_cast<float>(media.width);
  playback.height = static_cast<float>(media.height);

  if (!context || !context->source || media.file_path.empty()) {
    return playback;
  }

  obs_data_t *settings = obs_data_create();
  obs_data_set_bool(settings, "is_local_file", true);
  obs_data_set_string(settings, "local_file", media.file_path.c_str());
  obs_data_set_bool(settings, "looping", media.loop);
  obs_data_set_bool(settings, "restart_on_activate", true);
  obs_data_set_bool(settings, "close_when_inactive", false);
  obs_data_set_bool(settings, "clear_on_media_end", false);
  obs_data_set_bool(settings, "hw_decode", false);

  std::string name = std::string(obs_source_get_name(context->source)) + " Media " + std::to_string(index + 1);
  playback.source = obs_source_create_private("ffmpeg_source", name.c_str(), settings);
  obs_data_release(settings);

  if (!playback.source) {
    blog(
      LOG_WARNING,
      "[PPTBridge] Could not create ffmpeg media child for '%s'",
      media.file_path.c_str());
  } else {
    obs_source_add_audio_capture_callback(playback.source, forward_child_audio_for_meter, context);
    playback.audio_capture_registered = true;
  }

  return playback;
}

void sync_media_sources(SourceContext *context)
{
  if (!visual_child_sources_wanted(context)) {
    {
      if (context) {
        std::lock_guard<std::mutex> lock(context->media_mutex);
        context->media_signature.clear();
      }
    }
    clear_media_sources(context);
    return;
  }

  if (context->use_live_powerpoint && context->document && context->document->IsLivePowerPointReady()) {
    {
      std::lock_guard<std::mutex> lock(context->media_mutex);
      context->media_signature.clear();
    }
    clear_media_sources(context);
    return;
  }

  if (!context->document || context->pptx_path.empty()) {
    {
      std::lock_guard<std::mutex> lock(context->media_mutex);
      context->media_signature.clear();
    }
    clear_media_sources(context);
    return;
  }

  const auto media_items = context->document->CurrentMedia();
  const auto signature = build_media_signature(media_items);
  bool signature_changed = false;
  {
    std::lock_guard<std::mutex> lock(context->media_mutex);
    if (signature != context->media_signature) {
      context->media_signature = signature;
      signature_changed = true;
    }
  }

  if (signature_changed) {
    clear_media_sources(context);

    std::vector<SourceContext::MediaPlayback> playback;
    playback.reserve(media_items.size());
    for (size_t index = 0; index < media_items.size(); ++index) {
      playback.push_back(create_media_playback(context, media_items[index], index));
    }

    {
      std::lock_guard<std::mutex> lock(context->media_mutex);
      context->media_playback = std::move(playback);
    }
  }

  sync_media_playback_activity(context);
}

void render_media_overlay(SourceContext *context)
{
  if (!visual_child_sources_wanted(context) || !context->document || context->document->IsBlackScreen()) {
    return;
  }

  auto playback = snapshot_media_playback(context);
  bool rendered_any = false;
  for (auto &media : playback) {
    if (!media.source || !media.is_video || media.width <= 0.0f || media.height <= 0.0f) {
      continue;
    }

    const uint32_t media_width = obs_source_get_width(media.source);
    const uint32_t media_height = obs_source_get_height(media.source);
    if (media_width == 0 || media_height == 0) {
      continue;
    }

    rendered_any = true;
    gs_matrix_push();
    gs_matrix_translate3f(media.x * context->width, media.y * context->height, 0.0f);
    gs_matrix_scale3f(
      (media.width * context->width) / static_cast<float>(media_width),
      (media.height * context->height) / static_cast<float>(media_height),
      1.0f);
    obs_source_video_render(media.source);
    gs_matrix_pop();
  }

  if (!rendered_any) {
    release_media_playback_snapshot(playback);
    return;
  }

  release_media_playback_snapshot(playback);
}

void mix_audio(float *out, float *in, size_t pos, size_t count)
{
  float *dest = out + pos;
  float *src = in;
  float *end = in + count;
  while (src < end) {
    *(dest++) += *(src++);
  }
}

void mix_audio_with_gain(float *out, float *in, size_t pos, size_t count, float gain)
{
  if (gain == 1.0f) {
    mix_audio(out, in, pos, count);
    return;
  }

  float *dest = out + pos;
  float *src = in;
  float *end = in + count;
  while (src < end) {
    *(dest++) += (*(src++) * gain);
  }
}

float audio_gain_multiplier_db(double gain_db)
{
  return static_cast<float>(std::pow(10.0, gain_db / 20.0));
}

void forward_child_audio_for_meter(
  void *param,
  obs_source_t *source,
  const struct audio_data *audio_data,
  bool muted)
{
  auto *context = static_cast<SourceContext *>(param);
  if (!context || !context->source || !audio_data || audio_data->frames == 0 ||
      context->mode != ViewMode::Slide || !context->audio_enabled.load(std::memory_order_relaxed) || muted) {
    return;
  }

  struct obs_audio_info audio_info = {};
  if (!obs_get_audio_info(&audio_info)) {
    return;
  }

  const size_t channel_count = std::min<size_t>(get_audio_channels(audio_info.speakers), MAX_AUDIO_CHANNELS);
  const float gain = audio_gain_multiplier_db(context->audio_gain_db.load(std::memory_order_relaxed));
  std::array<std::vector<float>, MAX_AUDIO_CHANNELS> scaled;
  struct obs_source_audio output = {};
  for (size_t channel = 0; channel < channel_count; ++channel) {
    if (!audio_data->data[channel]) {
      continue;
    }
    if (gain == 1.0f) {
      output.data[channel] = audio_data->data[channel];
      continue;
    }

    const float *input = reinterpret_cast<const float *>(audio_data->data[channel]);
    scaled[channel].resize(audio_data->frames);
    std::transform(
      input,
      input + audio_data->frames,
      scaled[channel].begin(),
      [gain](float sample) { return sample * gain; });
    output.data[channel] = reinterpret_cast<const uint8_t *>(scaled[channel].data());
  }

  output.frames = audio_data->frames;
  output.speakers = audio_info.speakers;
  output.format = AUDIO_FORMAT_FLOAT_PLANAR;
  output.samples_per_sec = audio_info.samples_per_sec;
  output.timestamp = audio_data->timestamp;
  obs_source_output_audio(context->source, &output);
  (void)source;
}

std::string format_timer_seconds(uint64_t seconds)
{
  std::ostringstream stream;
  stream << (seconds / 60) << ":";
  const auto remaining = seconds % 60;
  if (remaining < 10) {
    stream << "0";
  }
  stream << remaining;
  return stream.str();
}

std::string summarize_operator_text(const std::string &text)
{
  constexpr size_t kMaxOperatorTextLength = 72;
  if (text.size() <= kMaxOperatorTextLength) {
    return text;
  }
  return text.substr(0, kMaxOperatorTextLength - 3) + "...";
}

std::string lowercase_ascii(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

std::string file_extension_lower(const std::string &path)
{
  const auto dot = path.find_last_of('.');
  const auto slash = path.find_last_of("/\\");
  if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) {
    return "";
  }
  return lowercase_ascii(path.substr(dot));
}

bool is_pdf_deck_path(const std::string &path)
{
  return file_extension_lower(path) == ".pdf";
}

bool is_pptx_deck_path(const std::string &path)
{
  return file_extension_lower(path) == ".pptx";
}

bool selected_deck_is_pdf(const SourceContext *context)
{
  return context && is_pdf_deck_path(context->pptx_path);
}

bool selected_deck_is_pptx(const SourceContext *context)
{
  return context && is_pptx_deck_path(context->pptx_path);
}

bool should_show_powerpoint_live_controls(const SourceContext *context)
{
  // Show the live controls before a file is selected so new users can see
  // where the controls will be, but hide them once the selected deck is a PDF.
  return !context || context->pptx_path.empty() || selected_deck_is_pptx(context);
}

std::string describe_operator_status(const PresentationStatus &snapshot, bool pdf_deck, bool pptx_deck)
{
  std::ostringstream status;
  status << "Operator status: ";
  if (!pdf_deck && !pptx_deck && snapshot.total_slides == 0) {
    status << "select a .pptx or .pdf deck";
  } else if (snapshot.total_slides == 0) {
    status << "no loaded cues yet";
  } else {
    status << "slide " << snapshot.current_slide << " / " << snapshot.total_slides;
    if (!snapshot.current_title.empty()) {
      status << "\nCurrent cue: " << summarize_operator_text(snapshot.current_title);
    }
  }
  if (!snapshot.next_title.empty()) {
    status << "\nNext cue: " << summarize_operator_text(snapshot.next_title);
  } else if (snapshot.total_slides > 0) {
    status << "\nNext cue: end of deck";
  }
  status << "\nChecked cues: " << snapshot.checked_count;
  status << "\nTimer: " << format_timer_seconds(snapshot.timer_seconds);
  status << "\nLive: ";
  if (pdf_deck) {
    status << "PDF render (PowerPoint live mode not needed)";
  } else if (snapshot.live_ready) {
    status << "PowerPoint attached";
  } else if (snapshot.live_enabled) {
    status << "waiting / cached fallback";
  } else {
    status << "cached PPT render";
  }
  if (snapshot.black_screen) {
    status << "\nBlack screen is ON";
  }
  return status.str();
}

std::string build_status_text(SourceContext *context);

void refresh_operator_status_property(obs_properties_t *properties, SourceContext *context)
{
  if (!properties || !context || !context->document) {
    return;
  }

  obs_property_t *status_property = obs_properties_get(properties, "pptbridge_operator_status");
  if (status_property) {
    const auto status = describe_operator_status(
      context->document->SnapshotStatus(),
      selected_deck_is_pdf(context),
      selected_deck_is_pptx(context));
    obs_property_set_description(status_property, status.c_str());
  }

  obs_property_t *source_status_property = obs_properties_get(properties, "pptbridge_status");
  if (source_status_property) {
    const auto source_status = build_status_text(context);
    obs_property_set_description(source_status_property, source_status.c_str());
  }
}

bool send_osc_status(SourceContext *context, bool force)
{
  if (!context || !context->document || !context->osc_feedback_enabled) {
    return false;
  }

  const auto state_version = context->document->StateVersion();
  const auto timer_second = context->document->PresentationSeconds();
  if (!force &&
      context->osc_feedback_last_state_version == state_version &&
      context->osc_feedback_last_timer_second == timer_second) {
    return false;
  }

  auto snapshot = context->document->SnapshotStatus();
  if (context->source) {
    if (const char *source_name = obs_source_get_name(context->source)) {
      snapshot.source_name = source_name;
    }
  }
  const bool ok = SendOscStatusFeedback(context->osc_feedback_host, context->osc_feedback_port, snapshot);
  context->osc_feedback_last_state_version = state_version;
  context->osc_feedback_last_timer_second = timer_second;
  context->osc_feedback_status = ok
    ? "OSC status sent to " + context->osc_feedback_host + ":" + std::to_string(context->osc_feedback_port)
    : "OSC status failed for " + context->osc_feedback_host + ":" + std::to_string(context->osc_feedback_port);
  return ok;
}

std::string build_status_text(SourceContext *context)
{
  std::ostringstream status;
  status << "Source status:\n";

  if (!context || !context->document) {
    status << "Presentation: not selected\n";
    status << "Live mode: " << ((context && context->use_live_powerpoint) ? "enabled" : "disabled");
    return status.str();
  }

  const auto live_enabled = context->document->IsLivePowerPointEnabled();
  const auto live_ready = context->document->IsLivePowerPointReady();
  const auto loading = context->document->IsLoading();
  const auto loaded = context->document->IsLoaded();
  const auto slide_count = context->document->SlideCount();
  const auto current_slide = slide_count > 0 ? (context->document->CurrentIndex() + 1) : 0;
  const auto last_error = context->document->LastError();
  const auto snapshot = context->document->SnapshotStatus();
  const auto live_children = snapshot_live_child_status(context);

  status << "Presentation: " << context->document->Name() << "\n";
  status << "Mode: " << (live_enabled ? "True Live PowerPoint" : "Legacy Render") << "\n";
  status << "Load state: ";
  if (live_ready && loading) {
    status << "live ready, preparing presenter";
  } else if (loading) {
    status << "loading";
  } else if (live_ready) {
    status << "live ready";
  } else if (loaded) {
    status << "ready";
  } else {
    status << "idle";
  }
  status << "\n";
  status << "Slide: " << current_slide << " / " << slide_count << "\n";
  if (!snapshot.current_title.empty()) {
    status << "Current cue: " << snapshot.current_title << "\n";
  }
  if (!snapshot.next_title.empty()) {
    status << "Next cue: " << snapshot.next_title << "\n";
  }
  status << "Checked cues: " << snapshot.checked_count << "\n";

  const auto kind = context->mode == ViewMode::Slide ? RegisteredSourceKind::Slide : RegisteredSourceKind::Presenter;
  const auto matching_sources = Registry::Instance().CountSources(context->pptx_path, kind);
  status << "Matching "
         << (context->mode == ViewMode::Slide ? "slide" : "presenter")
         << " sources for this deck: " << matching_sources << "\n";

  if (live_enabled) {
    status << "Live window: ";
    if (!live_children.capture_window_title.empty()) {
      status << live_children.capture_window_title;
    } else if (!context->document->LiveWindowTitle().empty()) {
      status << context->document->LiveWindowTitle();
    } else {
      status << "waiting";
    }
    status << "\n";

    if (context->mode == ViewMode::Slide) {
      status << "Live capture: ";
      if (live_capture_is_renderable(context)) {
        status << "attached";
      } else if (live_children.capture_present && live_children.capture_window_id != 0) {
        status << "attaching video frames";
      } else if (live_ready) {
        status << "searching for slideshow window";
      } else {
        status << "not ready";
      }
      status << "\n";
      status << "PowerPoint resize: "
             << (context->live_capture_resize_mode == LiveCaptureResizeMode::FitWindow
                   ? "following PowerPoint window"
                   : "locked to OBS canvas")
             << "\n";
      status << "Auto recover: " << (context->auto_recover_live ? "enabled" : "manual only") << "\n";
    } else {
      status << "Presenter output: cached confidence view; the matching PPTBridge SK Slide source carries live animations and video\n";
    }
  }

  status << "Audio: "
         << (context->audio_enabled.load(std::memory_order_relaxed) ? "enabled" : "muted")
         << ", gain " << context->audio_gain_db.load(std::memory_order_relaxed) << " dB";
  if (context->mode == ViewMode::Slide) {
    status << "\nPowerPoint app audio: ";
    if (!context->use_live_app_audio) {
      status << "disabled";
    } else if (!live_enabled) {
      status << "available in true live mode";
    } else if (live_children.audio_present) {
      status << "attached";
      if (!live_children.audio_application.empty()) {
        status << " (" << live_children.audio_application << ")";
      }
    } else if (live_ready) {
      status << "searching for PowerPoint app audio";
    } else {
      status << "not ready";
    }
    status << "\nStudio Mode note: OBS mixer follows the PPTBridge slide source that is currently live in Program.";
    if (matching_sources > 1) {
      status << "\nWarning: multiple PPTBridge SK Slide sources point to this same deck. Use Add Existing for live shows so one shared source owns audio and state.";
    }
  } else if (matching_sources > 1) {
    status << "\nWarning: multiple presenter sources point to this same deck.";
  }

  if (context->mode == ViewMode::Presenter && !context->cue_export_status.empty()) {
    status << "\nCue list: " << context->cue_export_status;
  }
  if (context->osc_feedback_enabled) {
    status << "\nOSC feedback: " << context->osc_feedback_host << ":" << context->osc_feedback_port;
    if (!context->osc_feedback_status.empty()) {
      status << " (" << context->osc_feedback_status << ")";
    }
  }

  if (!last_error.empty()) {
    status << "\nLast issue: " << last_error;
  }

  return status.str();
}

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
      context->stride,
      context->presenter_options);
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
  return true;
}

bool control_previous(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.Previous();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_next(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.Next();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_first(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.First();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_last(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.Last();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_black(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.ToggleBlackScreen();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_reload(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  const bool handled = with_active_document(context, [](PresentationDocument &document) {
    document.ReloadAsync();
  });
  refresh_operator_status_property(properties, context);
  return handled;
}

bool control_export_cue_list(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  std::string output_path;
  std::string error;
  if (context->document->ExportCueList(output_path, error)) {
    context->cue_export_status = "exported to " + output_path;
    blog(LOG_INFO, "[PPTBridge SK] Exported cue list to '%s'", output_path.c_str());
  } else {
    context->cue_export_status = error.empty() ? "export failed" : error;
    blog(LOG_WARNING, "[PPTBridge SK] Cue list export failed: %s", context->cue_export_status.c_str());
  }
  return true;
}

bool control_toggle_current_cue(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  Registry::Instance().SetActive(context->document);
  const auto snapshot = context->document->SnapshotStatus();
  if (snapshot.current_slide == 0) {
    context->cue_export_status = "no current cue yet";
    return true;
  }

  context->document->ToggleCueChecked(snapshot.current_index);
  context->cue_export_status = "toggled current cue " + std::to_string(snapshot.current_slide);
  send_osc_status(context, true);
  refresh_operator_status_property(properties, context);
  return true;
}

bool control_toggle_next_cue(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  Registry::Instance().SetActive(context->document);
  const auto snapshot = context->document->SnapshotStatus();
  if (snapshot.current_slide == 0 || snapshot.current_index + 1 >= snapshot.total_slides) {
    context->cue_export_status = "no next cue to toggle";
    return true;
  }

  context->document->ToggleCueChecked(snapshot.current_index + 1);
  context->cue_export_status = "toggled next cue " + std::to_string(snapshot.current_index + 2);
  send_osc_status(context, true);
  refresh_operator_status_property(properties, context);
  return true;
}

bool control_clear_cue_checks(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  context->document->ClearCueChecks();
  context->cue_export_status = "cleared cue checks";
  send_osc_status(context, true);
  refresh_operator_status_property(properties, context);
  return true;
}

bool control_send_osc_status(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  if (!context->osc_feedback_enabled) {
    context->osc_feedback_status = "enable OSC feedback first";
    return true;
  }

  send_osc_status(context, true);
  return true;
}

void for_each_matching_slide_source(
  SourceContext *requesting_context,
  const std::function<void(SourceContext *)> &callback)
{
  if (!requesting_context || requesting_context->pptx_path.empty() || !callback) {
    return;
  }

  const auto tokens = Registry::Instance().SourceTokens(
    requesting_context->pptx_path,
    RegisteredSourceKind::Slide);
  for (void *token : tokens) {
    auto *slide_context = static_cast<SourceContext *>(token);
    if (!slide_context || !slide_context->source) {
      continue;
    }

    callback(slide_context);
  }
}

void reset_live_child_sources(SourceContext *context, bool suppress_auto_recovery)
{
  if (!context) {
    return;
  }

  release_live_capture_source(context);
  clear_live_audio_source(context);
  context->live_capture_missing_since = std::chrono::steady_clock::time_point::min();
  context->live_recover_last_attempt = std::chrono::steady_clock::time_point::min();
  context->live_reload_last_attempt = std::chrono::steady_clock::time_point::min();
  context->live_watchdog_ready = false;
  context->live_capture_suppressed_after_stop = suppress_auto_recovery;
  if (suppress_auto_recovery) {
    context->started_live_powerpoint_from_this_source = false;
  }
}

void enable_live_mode_for_matching_slide_sources(SourceContext *requesting_context)
{
  for_each_matching_slide_source(requesting_context, [](SourceContext *slide_context) {
    reset_live_child_sources(slide_context, false);

    obs_data_t *settings = obs_source_get_settings(slide_context->source);
    if (!settings) {
      return;
    }
    if (!obs_data_get_bool(settings, "use_live_powerpoint")) {
      obs_data_set_bool(settings, "use_live_powerpoint", true);
      obs_source_update(slide_context->source, settings);
    }
    obs_data_release(settings);
  });
}

void stop_live_mode_for_matching_slide_sources(SourceContext *requesting_context)
{
  for_each_matching_slide_source(requesting_context, [](SourceContext *slide_context) {
    reset_live_child_sources(slide_context, true);
  });
}

void reattach_live_mode_for_matching_slide_sources(SourceContext *requesting_context)
{
  for_each_matching_slide_source(requesting_context, [](SourceContext *slide_context) {
    reset_live_child_sources(slide_context, false);
  });
}

bool control_start_live(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return false;
  }
  if (!selected_deck_is_pptx(context)) {
    context->cue_export_status = "PowerPoint Live Mode is only available for .pptx decks; PDF decks are controlled directly by PPTBridge.";
    blog(
      LOG_INFO,
      "[PPTBridge SK] Ignoring PowerPoint live start for non-PPTX deck '%s'",
      context->pptx_path.c_str());
    return true;
  }

  enable_live_mode_for_matching_slide_sources(context);
  if (!context->document) {
    return false;
  }

  Registry::Instance().SetActive(context->document);
  reset_live_child_sources(context, false);
  context->started_live_powerpoint_from_this_source = true;
  context->document->StartLivePowerPointAsync();
  refresh_operator_status_property(properties, context);
  return true;
}

bool control_stop_live(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return false;
  }
  if (!selected_deck_is_pptx(context)) {
    context->cue_export_status = "PDF decks do not use PowerPoint Live Mode.";
    return true;
  }

  stop_live_mode_for_matching_slide_sources(context);
  reset_live_child_sources(context, true);
  context->document->StopLivePowerPointAsync();
  refresh_operator_status_property(properties, context);
  return true;
}

void set_live_capture_resize_mode(SourceContext *context, LiveCaptureResizeMode mode)
{
  if (!context) {
    return;
  }

  context->live_capture_resize_mode = mode;
  if (!context->source) {
    return;
  }

  obs_data_t *settings = obs_source_get_settings(context->source);
  if (!settings) {
    return;
  }
  obs_data_set_string(settings, "live_capture_resize_mode", live_capture_resize_mode_to_setting(mode));
  obs_source_update(context->source, settings);
  obs_data_release(settings);
}

bool control_lock_live_resize(obs_properties_t *, obs_property_t *, void *data)
{
  set_live_capture_resize_mode(static_cast<SourceContext *>(data), LiveCaptureResizeMode::LockCanvas);
  return true;
}

bool control_follow_live_resize(obs_properties_t *, obs_property_t *, void *data)
{
  set_live_capture_resize_mode(static_cast<SourceContext *>(data), LiveCaptureResizeMode::FitWindow);
  return true;
}

bool control_reattach_live(obs_properties_t *properties, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context) {
    return false;
  }

  reattach_live_mode_for_matching_slide_sources(context);
  reset_live_child_sources(context, false);
  if (context->document) {
    Registry::Instance().SetActive(context->document);
    context->document->SyncLiveStateAsync();
  }
  refresh_operator_status_property(properties, context);
  return true;
}

void add_operator_mode_properties(obs_properties_t *props, SourceContext *context)
{
  obs_properties_t *operator_props = obs_properties_create();
  PresentationStatus snapshot;
  if (context && context->document) {
    snapshot = context->document->SnapshotStatus();
  }
  const bool pdf_deck = selected_deck_is_pdf(context);
  const bool pptx_deck = selected_deck_is_pptx(context);
  const bool show_live_controls = should_show_powerpoint_live_controls(context);
  const char *operator_help_text = pdf_deck
    ? "Use this panel during the show: move PDF pages, mark cues, and send Companion/OSC status. PDF decks do not need PowerPoint Live Mode."
    : "Use this panel during the show: start live mode if needed, move slides, mark cues, and send Companion/OSC status.";

  obs_property_t *operator_help = obs_properties_add_text(
    operator_props,
    "pptbridge_operator_help",
    operator_help_text,
    OBS_TEXT_INFO);
  obs_property_text_set_info_type(operator_help, pdf_deck ? OBS_TEXT_INFO_NORMAL : OBS_TEXT_INFO_WARNING);
  obs_property_text_set_info_word_wrap(operator_help, true);

  if (show_live_controls) {
    obs_properties_add_button(
      operator_props,
      "pptbridge_operator_start_live_btn",
      "Start / Restart PowerPoint Live Mode",
      control_start_live);
    obs_properties_add_button(
      operator_props,
      "pptbridge_operator_stop_live_btn",
      "Stop PowerPoint Live Mode",
      control_stop_live);
  }
  obs_properties_add_button(operator_props, "pptbridge_operator_previous_btn", "Previous Slide", control_previous);
  obs_properties_add_button(operator_props, "pptbridge_operator_next_btn", "Next Slide", control_next);
  obs_properties_add_button(
    operator_props,
    "pptbridge_cue_toggle_current_btn",
    "Check / Uncheck Current Cue",
    control_toggle_current_cue);
  obs_properties_add_button(
    operator_props,
    "pptbridge_cue_toggle_next_btn",
    "Check / Uncheck Next Cue",
    control_toggle_next_cue);
  obs_properties_add_button(
    operator_props,
    "pptbridge_cue_clear_checks_btn",
    "Clear Cue Checks",
    control_clear_cue_checks);

  const std::string operator_status = describe_operator_status(snapshot, pdf_deck, pptx_deck);
  obs_property_t *operator_status_prop = obs_properties_add_text(
    operator_props,
    "pptbridge_operator_status",
    operator_status.c_str(),
    OBS_TEXT_INFO);
  obs_property_text_set_info_type(operator_status_prop, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(operator_status_prop, true);

  obs_properties_add_bool(operator_props, "pptbridge_osc_feedback_enabled", "Send OSC Status Feedback");
  obs_properties_add_text(
    operator_props,
    "pptbridge_osc_feedback_host",
    "OSC Status Host/IP",
    OBS_TEXT_DEFAULT);
  obs_properties_add_int(operator_props, "pptbridge_osc_feedback_port", "OSC Status Port", 1, 65535, 1);
  obs_properties_add_button(
    operator_props,
    "pptbridge_send_osc_status_btn",
    "Send OSC Status Now",
    control_send_osc_status);

  obs_properties_add_group(
    props,
    "pptbridge_operator_group",
    "Show Control (Operator Mode)",
    OBS_GROUP_NORMAL,
    operator_props);
}

}  // namespace

void source_defaults(obs_data_t *settings)
{
  obs_data_set_default_string(settings, "pptx_path", "");
  obs_data_set_default_int(settings, "canvas_width", 1920);
  obs_data_set_default_int(settings, "canvas_height", 1080);
  obs_data_set_default_bool(settings, "use_live_powerpoint", true);
  obs_data_set_default_bool(settings, "auto_start_live_powerpoint", false);
  obs_data_set_default_bool(settings, "close_live_powerpoint_on_shutdown", true);
  obs_data_set_default_string(settings, "live_capture_resize_mode", "lock_canvas");
  obs_data_set_default_bool(settings, "audio_enabled", true);
  obs_data_set_default_bool(settings, "use_live_app_audio", true);
  obs_data_set_default_bool(settings, "auto_recover_live", true);
  obs_data_set_default_double(settings, "audio_gain_db", 0.0);
  obs_data_set_default_string(settings, "presenter_layout", "balanced");
  obs_data_set_default_string(settings, "presenter_preview_scale_mode", "fit");
  obs_data_set_default_double(settings, "presenter_preview_scale_percent", 100.0);
  obs_data_set_default_double(settings, "presenter_preview_position_x", 0.0);
  obs_data_set_default_double(settings, "presenter_preview_position_y", 0.0);
  obs_data_set_default_double(settings, "presenter_side_panel_width_percent", 100.0);
  obs_data_set_default_double(settings, "presenter_notes_font_size", 16.0);
  obs_data_set_default_double(settings, "presenter_notes_area_percent", 100.0);
  obs_data_set_default_double(settings, "presenter_notes_zoom_percent", 100.0);
  obs_data_set_default_double(settings, "presenter_notes_position_y", 0.0);
  obs_data_set_default_int(settings, "presenter_background_color", 0x0d121a);
  obs_data_set_default_string(settings, "presenter_background_image_path", "");
  obs_data_set_default_string(settings, "presenter_background_image_mode", "watermark");
  obs_data_set_default_double(settings, "presenter_background_image_opacity_percent", 22.0);
  obs_data_set_default_bool(settings, "presenter_show_cue_list", false);
  obs_data_set_default_bool(settings, "pptbridge_osc_feedback_enabled", false);
  obs_data_set_default_string(settings, "pptbridge_osc_feedback_host", "127.0.0.1");
  obs_data_set_default_int(settings, "pptbridge_osc_feedback_port", 57131);
}

obs_properties_t *source_properties(SourceContext *context)
{
  obs_properties_t *props = obs_properties_create_param(context, nullptr);
  const bool pdf_deck = selected_deck_is_pdf(context);
  const bool show_live_controls = should_show_powerpoint_live_controls(context);
  // The source accepts both PowerPoint decks (.pptx) and PDF presentations
  // (.pdf) — PDFs are rendered natively via PDFKit so guest speakers who
  // only bring a PDF can still run their deck through PPTBridge without
  // requiring PowerPoint or LibreOffice.
  obs_properties_add_path(
    props,
    "pptx_path",
    "Presentation File (.pptx or .pdf)",
    OBS_PATH_FILE,
    "Presentations (*.pptx *.pdf);;PowerPoint (*.pptx);;PDF (*.pdf)",
    nullptr);
  add_operator_mode_properties(props, context);
  // The Slide source is hard-locked to Full HD (1920x1080) so the program
  // feed is always clean 16:9 broadcast-ready output. Only the Presenter
  // source exposes canvas size controls, since confidence monitors may
  // have non-standard resolutions.
  if (context && context->mode == ViewMode::Presenter) {
    obs_properties_add_int(props, "canvas_width", "Canvas Width", 320, 7680, 1);
    obs_properties_add_int(props, "canvas_height", "Canvas Height", 240, 4320, 1);
    add_presenter_customization_properties(props);
    obs_properties_add_button(props, "pptbridge_export_cue_list_btn", "Export Cue List (.txt)", control_export_cue_list);

    if (show_live_controls) {
      obs_properties_t *presenter_live_controls = obs_properties_create();
      obs_property_t *presenter_live_control_help =
        obs_properties_add_text(
          presenter_live_controls,
          "pptbridge_presenter_live_control_help",
          "Use START if this presenter source should launch the PowerPoint slideshow for this deck. Presenter view stays lightweight and static; use PPTBridge SK Slide for live animations and video.",
          OBS_TEXT_INFO);
      obs_property_text_set_info_type(presenter_live_control_help, OBS_TEXT_INFO_WARNING);
      obs_property_text_set_info_word_wrap(presenter_live_control_help, true);
      obs_properties_add_button(
        presenter_live_controls,
        "pptbridge_presenter_start_live_btn",
        "Start / Restart PowerPoint Live Mode",
        control_start_live);
      obs_properties_add_button(
        presenter_live_controls,
        "pptbridge_presenter_stop_live_btn",
        "Stop PowerPoint Live Mode",
        control_stop_live);
      obs_properties_add_group(
        props,
        "pptbridge_presenter_live_controls_group",
        "PowerPoint Live Start / Stop",
        OBS_GROUP_NORMAL,
        presenter_live_controls);
    }
  }
  if (context && context->mode == ViewMode::Slide) {
    if (show_live_controls) {
      obs_properties_add_bool(props, "use_live_powerpoint", "Use True Live PowerPoint Mode");
      obs_properties_add_bool(props, "auto_start_live_powerpoint", "Auto Start PowerPoint When OBS Opens");
      obs_properties_add_bool(props, "close_live_powerpoint_on_shutdown", "Close PowerPoint Slideshow When OBS Closes");

      obs_properties_t *live_controls = obs_properties_create();
      obs_property_t *live_control_help =
        obs_properties_add_text(live_controls, "pptbridge_live_control_help", kLiveControlHelp, OBS_TEXT_INFO);
      obs_property_text_set_info_type(live_control_help, OBS_TEXT_INFO_WARNING);
      obs_property_text_set_info_word_wrap(live_control_help, true);
      obs_properties_add_button(
        live_controls,
        "pptbridge_start_live_btn",
        "Start / Restart PowerPoint Live Mode",
        control_start_live);
      obs_properties_add_button(
        live_controls,
        "pptbridge_stop_live_btn",
        "Stop PowerPoint Live Mode",
        control_stop_live);
      obs_properties_add_group(
        props,
        "pptbridge_live_controls_group",
        "PowerPoint Live Start / Stop",
        OBS_GROUP_NORMAL,
        live_controls);

      obs_property_t *resize_mode = obs_properties_add_list(
        props,
        "live_capture_resize_mode",
        "PowerPoint Resize Behavior",
        OBS_COMBO_TYPE_LIST,
        OBS_COMBO_FORMAT_STRING);
      obs_property_list_add_string(resize_mode, "Lock OBS Output Size", "lock_canvas");
      obs_property_list_add_string(resize_mode, "Follow PowerPoint Window Size", "fit_window");
      obs_properties_add_bool(props, "use_live_app_audio", "Route PowerPoint App Audio Through OBS");
      obs_properties_add_bool(props, "auto_recover_live", "Auto Recover Live PowerPoint Session");
    } else if (pdf_deck) {
      obs_property_t *pdf_live_note = obs_properties_add_text(
        props,
        "pptbridge_pdf_live_note",
        "PDF deck selected: PPTBridge renders and controls pages directly. PowerPoint Live Mode, PowerPoint resize controls, and PowerPoint app-audio routing are only shown for .pptx files.",
        OBS_TEXT_INFO);
      obs_property_text_set_info_type(pdf_live_note, OBS_TEXT_INFO_NORMAL);
      obs_property_text_set_info_word_wrap(pdf_live_note, true);
    }
    obs_properties_add_bool(props, "audio_enabled", "Enable PPTBridge Audio Output");
    obs_properties_add_float_slider(props, "audio_gain_db", "Audio Gain (dB)", -30.0, 18.0, 0.5);
  }

  const std::string status_text = build_status_text(context);
  obs_property_t *status = obs_properties_add_text(props, "pptbridge_status", status_text.c_str(), OBS_TEXT_INFO);
  obs_property_text_set_info_type(status, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(status, true);

  obs_property_t *help = obs_properties_add_text(props, "pptbridge_help", kHotkeyHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(help, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(help, true);

  if (show_live_controls) {
    obs_property_t *live_help = obs_properties_add_text(props, "pptbridge_live_help", kLiveHelp, OBS_TEXT_INFO);
    obs_property_text_set_info_type(live_help, OBS_TEXT_INFO_NORMAL);
    obs_property_text_set_info_word_wrap(live_help, true);
  }

  if (context && context->mode == ViewMode::Slide && show_live_controls) {
    obs_property_t *resize_help =
      obs_properties_add_text(props, "pptbridge_live_resize_help", kLiveResizeHelp, OBS_TEXT_INFO);
    obs_property_text_set_info_type(resize_help, OBS_TEXT_INFO_NORMAL);
    obs_property_text_set_info_word_wrap(resize_help, true);
  }

  obs_property_t *media_help = obs_properties_add_text(props, "pptbridge_media_help", kMediaHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(media_help, OBS_TEXT_INFO_WARNING);
  obs_property_text_set_info_word_wrap(media_help, true);

  if (context && context->mode == ViewMode::Slide && show_live_controls) {
    obs_property_t *audio_help = obs_properties_add_text(props, "pptbridge_audio_help", kAudioHelp, OBS_TEXT_INFO);
    obs_property_text_set_info_type(audio_help, OBS_TEXT_INFO_NORMAL);
    obs_property_text_set_info_word_wrap(audio_help, true);
  }

  obs_properties_add_button(props, "pptbridge_prev_btn", "Previous Slide", control_previous);
  obs_properties_add_button(props, "pptbridge_next_btn", "Next Slide", control_next);
  obs_properties_add_button(props, "pptbridge_first_btn", "First Slide", control_first);
  obs_properties_add_button(props, "pptbridge_last_btn", "Last Slide", control_last);
  obs_properties_add_button(props, "pptbridge_black_btn", "Toggle Black Screen", control_black);
  obs_properties_add_button(props, "pptbridge_reload_btn", "Reload Presentation", control_reload);
  if (context && context->mode == ViewMode::Slide && show_live_controls) {
    obs_properties_add_button(props, "pptbridge_lock_live_resize_btn", "Lock OBS Size Against PPT Resize", control_lock_live_resize);
    obs_properties_add_button(props, "pptbridge_follow_live_resize_btn", "Follow Current PPT Window Size", control_follow_live_resize);
    obs_properties_add_button(props, "pptbridge_reattach_live_btn", "Reattach Live PowerPoint Window", control_reattach_live);
  }
  return props;
}

void source_update(SourceContext *context, obs_data_t *settings)
{
  if (!context) {
    return;
  }

  const char *path = obs_data_get_string(settings, "pptx_path");
  const std::string selected_path = path ? path : "";
  const bool powerpoint_live_available = is_pptx_deck_path(selected_path);
  // Slide source always renders at Full HD 1920x1080 regardless of any
  // stored canvas_width/canvas_height. Only the Presenter source honors
  // user-configurable canvas dimensions.
  const uint32_t width = (context->mode == ViewMode::Slide)
    ? 1920u
    : static_cast<uint32_t>(obs_data_get_int(settings, "canvas_width"));
  const uint32_t height = (context->mode == ViewMode::Slide)
    ? 1080u
    : static_cast<uint32_t>(obs_data_get_int(settings, "canvas_height"));
  const bool use_live_powerpoint = powerpoint_live_available && obs_data_get_bool(settings, "use_live_powerpoint");
  const bool auto_start_live_powerpoint =
    powerpoint_live_available && obs_data_get_bool(settings, "auto_start_live_powerpoint");
  const bool close_live_powerpoint_on_shutdown = obs_data_get_bool(settings, "close_live_powerpoint_on_shutdown");
  const LiveCaptureResizeMode live_capture_resize_mode =
    live_capture_resize_mode_from_setting(obs_data_get_string(settings, "live_capture_resize_mode"));
  const bool audio_enabled = obs_data_get_bool(settings, "audio_enabled");
  const bool use_live_app_audio = powerpoint_live_available && obs_data_get_bool(settings, "use_live_app_audio");
  const bool auto_recover_live = obs_data_get_bool(settings, "auto_recover_live");
  const double audio_gain_db = obs_data_get_double(settings, "audio_gain_db");
  const PresenterRenderOptions presenter_options = presenter_options_from_settings(settings);
  const bool osc_feedback_enabled = obs_data_get_bool(settings, "pptbridge_osc_feedback_enabled");
  const char *osc_feedback_host = obs_data_get_string(settings, "pptbridge_osc_feedback_host");
  const uint16_t osc_feedback_port =
    static_cast<uint16_t>(std::clamp<int64_t>(obs_data_get_int(settings, "pptbridge_osc_feedback_port"), 1, 65535));

  const std::shared_ptr<PresentationDocument> old_document = context->document;
  const bool old_use_live_powerpoint = context->use_live_powerpoint;
  const bool old_close_live_powerpoint_on_shutdown = context->close_live_powerpoint_on_shutdown;
  const bool path_changed = context->pptx_path != selected_path;
  const bool size_changed = context->width != width || context->height != height;
  const bool live_mode_changed = context->use_live_powerpoint != use_live_powerpoint;
  const bool live_auto_start_changed = context->auto_start_live_powerpoint != auto_start_live_powerpoint;
  const bool live_audio_mode_changed = context->use_live_app_audio != use_live_app_audio;
  const bool presenter_options_changed = !presenter_options_equal(context->presenter_options, presenter_options);
  const bool should_stop_old_live =
    context->mode == ViewMode::Slide &&
    old_document &&
    old_use_live_powerpoint &&
    old_close_live_powerpoint_on_shutdown &&
    (path_changed || (live_mode_changed && !use_live_powerpoint)) &&
    Registry::Instance().CountSources(context->pptx_path, RegisteredSourceKind::Slide) <= 1;

  if (should_stop_old_live) {
    release_live_capture_source(context);
    clear_live_audio_source(context);
    old_document->StopLivePowerPoint();
  }

  context->pptx_path = selected_path;
  if (path_changed) {
    context->cue_export_status.clear();
  }
  context->width = width;
  context->height = height;
  context->use_live_powerpoint = use_live_powerpoint;
  context->auto_start_live_powerpoint = auto_start_live_powerpoint;
  context->close_live_powerpoint_on_shutdown = close_live_powerpoint_on_shutdown;
  context->live_capture_resize_mode = live_capture_resize_mode;
  context->audio_enabled.store(audio_enabled, std::memory_order_relaxed);
  context->use_live_app_audio = use_live_app_audio;
  context->auto_recover_live = auto_recover_live;
  context->audio_gain_db.store(audio_gain_db, std::memory_order_relaxed);
  context->presenter_options = presenter_options;
  context->osc_feedback_enabled = osc_feedback_enabled;
  context->osc_feedback_host = (osc_feedback_host && *osc_feedback_host) ? osc_feedback_host : "127.0.0.1";
  context->osc_feedback_port = osc_feedback_port;
  if (path_changed || live_mode_changed) {
    context->osc_feedback_last_state_version = 0;
    context->osc_feedback_last_timer_second = 0;
    context->osc_feedback_status.clear();
  }

  if (!context->pptx_path.empty()) {
    Registry::Instance().AttachSource(
      context,
      context->pptx_path,
      context->mode == ViewMode::Slide ? RegisteredSourceKind::Slide : RegisteredSourceKind::Presenter);
  } else {
    Registry::Instance().DetachSource(context);
  }

  if (path_changed || live_mode_changed) {
    {
      std::lock_guard<std::mutex> lock(context->media_mutex);
      context->media_signature.clear();
    }
    clear_media_sources(context);
    release_live_capture_source(context);
    clear_live_audio_source(context);
    context->live_capture_missing_since = std::chrono::steady_clock::time_point::min();
    context->live_recover_last_attempt = std::chrono::steady_clock::time_point::min();
    context->live_reload_last_attempt = std::chrono::steady_clock::time_point::min();
    context->live_watchdog_ready = false;
    context->document.reset();
    if (!context->pptx_path.empty()) {
      context->document = Registry::Instance().Acquire(context->pptx_path);
    }
    if (context->document) {
      if (context->mode == ViewMode::Slide) {
        context->document->SetLivePowerPointEnabled(context->use_live_powerpoint);
        context->document->SetLivePowerPointAutoStart(context->auto_start_live_powerpoint);
      }
      if (context->mode == ViewMode::Presenter) {
        context->document->SetPresenterAssetsWanted(true);
      }
      context->document->EnsureLoadingAsync();
      Registry::Instance().SetActive(context->document);
    }
  } else if (live_auto_start_changed && context->document) {
    if (context->mode == ViewMode::Slide) {
      context->document->SetLivePowerPointAutoStart(context->auto_start_live_powerpoint);
      context->document->EnsureLoadingAsync();
    }
  } else if (live_audio_mode_changed) {
    clear_live_audio_source(context);
  } else if (context->document) {
    if (context->mode == ViewMode::Slide) {
      context->document->SetLivePowerPointEnabled(context->use_live_powerpoint);
      context->document->SetLivePowerPointAutoStart(context->auto_start_live_powerpoint);
    }
    if (context->mode == ViewMode::Presenter) {
      context->document->SetPresenterAssetsWanted(true);
    }
  }

  // Texture contents are refreshed by the render thread after the state reset
  // below. Only a dimension change requires destroying and recreating the GPU
  // texture; doing that for ordinary property edits can race the active render.
  if (size_changed) {
    source_destroy_texture(context);
  }

  context->rendered_state_version = 0;
  context->rendered_timer_second = 0;
}

void source_tick(SourceContext *context)
{
  if (context && context->document) {
    context->document->EnsureLoadingAsync();
    context->document->SyncLiveStateAsync();
    if (context->source && (obs_source_showing(context->source) || obs_source_active(context->source))) {
      Registry::Instance().SetActive(context->document);
    }
  }

  sync_live_capture_source(context);
  sync_live_audio_source(context);
  sync_media_sources(context);
  send_osc_status(context, false);

  if (!context || context->mode != ViewMode::Slide || !context->document) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  const bool live_capture_ready = live_capture_is_renderable(context);
  {
    std::lock_guard<std::mutex> lock(context->live_sources_mutex);
    context->live_capture_hooked = live_capture_ready;
  }
  if (live_capture_ready) {
    context->live_capture_last_seen = now;
    context->live_capture_missing_since = std::chrono::steady_clock::time_point::min();
    context->live_watchdog_ready = true;
  }
  if (snapshot_live_child_status(context).audio_present) {
    context->live_audio_last_seen = now;
  }

  const bool source_is_visible =
    context->source &&
    (obs_source_showing(context->source) || obs_source_active(context->source));
  const bool should_monitor_live =
    context->auto_recover_live &&
    context->use_live_powerpoint &&
    context->document->IsLivePowerPointEnabled() &&
    !context->live_capture_suppressed_after_stop &&
    source_is_visible;

  if (!should_monitor_live) {
    context->live_capture_missing_since = std::chrono::steady_clock::time_point::min();
    return;
  }

  if (!context->document->IsLivePowerPointReady()) {
    if (!context->live_watchdog_ready) {
      context->live_capture_missing_since = std::chrono::steady_clock::time_point::min();
      return;
    }

    if (context->live_capture_missing_since == std::chrono::steady_clock::time_point::min()) {
      context->live_capture_missing_since = now;
      return;
    }

    if (now - context->live_capture_missing_since >= kLiveRecoverRetryDelay &&
        (context->live_recover_last_attempt == std::chrono::steady_clock::time_point::min() ||
         now - context->live_recover_last_attempt >= kLiveRecoverRetryDelay)) {
      blog(LOG_WARNING, "[PPTBridge SK] Live slideshow session closed unexpectedly; restarting PowerPoint live mode");
      context->live_recover_last_attempt = now;
      context->live_capture_missing_since = now;
      release_live_capture_source(context);
      clear_live_audio_source(context);
      context->document->StartLivePowerPointAsync();
    }
    return;
  }

  if (live_capture_ready) {
    return;
  }

  if (context->live_capture_missing_since == std::chrono::steady_clock::time_point::min()) {
    context->live_capture_missing_since = now;
    return;
  }

  if (now - context->live_capture_missing_since >= kLiveRecoverRetryDelay &&
      (context->live_recover_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_recover_last_attempt >= kLiveRecoverRetryDelay)) {
    blog(LOG_WARNING, "[PPTBridge SK] Live slideshow has no video frames; recreating the capture source");
    context->live_recover_last_attempt = now;
    release_live_capture_source(context);
    clear_live_audio_source(context);
    context->document->SyncLiveStateAsync();
  }

  if (now - context->live_capture_missing_since >= kLiveReloadDelay &&
      (context->live_reload_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_reload_last_attempt >= kLiveReloadDelay)) {
    blog(LOG_WARNING, "[PPTBridge SK] Live slideshow capture did not recover; reloading presentation session");
    context->live_reload_last_attempt = now;
    release_live_capture_source(context);
    context->document->ReloadAsync();
  }
}

void source_destroy(SourceContext *context)
{
  if (!context) {
    return;
  }

  const bool owns_live_session =
    context->mode == ViewMode::Slide || context->started_live_powerpoint_from_this_source;
  Registry::Instance().DetachSource(context);
  if (owns_live_session &&
      context->close_live_powerpoint_on_shutdown &&
      context->document &&
      Registry::Instance().CountSources(context->pptx_path, RegisteredSourceKind::Slide) == 0) {
    context->document->StopLivePowerPoint();
  }

  release_live_capture_source(context);
  clear_live_audio_source(context);
  clear_media_sources(context);
  source_destroy_texture(context);
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

  if (context->mode == ViewMode::Slide && render_live_capture(context)) {
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

  render_media_overlay(context);
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
  source_destroy(context);
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

static void slide_source_activate(void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (context && context->document) {
    Registry::Instance().SetActive(context->document);
  }
  sync_live_capture_activity(context);
  sync_live_audio_activity(context);
  sync_media_playback_activity(context);
}

static void slide_source_deactivate(void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  sync_live_capture_activity(context);
  sync_live_audio_activity(context);
  sync_media_playback_activity(context);
}

static uint32_t slide_source_get_width(void *data)
{
  return source_width(static_cast<SourceContext *>(data));
}

static uint32_t slide_source_get_height(void *data)
{
  return source_height(static_cast<SourceContext *>(data));
}

static bool slide_source_audio_render(
  void *data,
  uint64_t *ts_out,
  struct obs_source_audio_mix *audio_output,
  uint32_t mixers,
  size_t channels,
  size_t sample_rate)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || context->mode != ViewMode::Slide) {
    return false;
  }
  if (!context->audio_enabled.load(std::memory_order_relaxed)) {
    return false;
  }

  const float gain = audio_gain_multiplier_db(context->audio_gain_db.load(std::memory_order_relaxed));

  auto playback = snapshot_audio_children(context);
  uint64_t timestamp = 0;
  for (const auto &media : playback) {
    if (!media.source || !media.is_audio || obs_source_audio_pending(media.source)) {
      continue;
    }

    const uint64_t source_ts = obs_source_get_audio_timestamp(media.source);
    if (source_ts != 0 && (!timestamp || source_ts < timestamp)) {
      timestamp = source_ts;
    }
  }

  if (!timestamp) {
    release_audio_children_snapshot(playback);
    *ts_out = os_gettime_ns();
    return true;
  }

  for (const auto &media : playback) {
    if (!media.source || !media.is_audio || obs_source_audio_pending(media.source)) {
      continue;
    }

    const uint64_t source_ts = obs_source_get_audio_timestamp(media.source);
    if (!source_ts) {
      continue;
    }

    const size_t pos = static_cast<size_t>(ns_to_audio_frames(sample_rate, source_ts - timestamp));
    if (pos >= AUDIO_OUTPUT_FRAMES) {
      continue;
    }

    struct obs_source_audio_mix child_audio = {};
    obs_source_get_audio_mix(media.source, &child_audio);
    const size_t count = AUDIO_OUTPUT_FRAMES - pos;
    for (size_t mix = 0; mix < MAX_AUDIO_MIXES; ++mix) {
      if ((mixers & (1u << mix)) == 0) {
        continue;
      }

      const size_t channel_count = std::min<size_t>(channels, MAX_AUDIO_CHANNELS);
      for (size_t channel = 0; channel < channel_count; ++channel) {
        float *out = audio_output->output[mix].data[channel];
        float *in = child_audio.output[mix].data[channel];
        if (!out || !in) {
          continue;
        }
        mix_audio_with_gain(out, in, pos, count, gain);
      }
    }
  }

  *ts_out = timestamp;
  release_audio_children_snapshot(playback);
  return true;
}

static void slide_source_enum_active_sources(void *data, obs_source_enum_proc_t enum_callback, void *param)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->source) {
    return;
  }

  std::vector<obs_source_t *> children;
  auto capture = snapshot_live_capture(context);
  if (capture.source && capture.active && capture.window_id != 0) {
    children.push_back(capture.source);
    capture.source = nullptr;
  }
  release_live_capture_snapshot(capture);

  auto audio = snapshot_live_audio(context);
  if (audio.source && audio.active) {
    children.push_back(audio.source);
    audio.source = nullptr;
  }
  release_live_audio_snapshot(audio);

  {
    std::lock_guard<std::mutex> lock(context->media_mutex);
    for (const auto &media : context->media_playback) {
      if (media.source && media.active_child) {
        if (obs_source_t *child = obs_source_get_ref(media.source)) {
          children.push_back(child);
        }
      }
    }
  }

  for (obs_source_t *child : children) {
    enum_callback(context->source, child, param);
    obs_source_release(child);
  }
}

static void slide_source_enum_all_sources(void *data, obs_source_enum_proc_t enum_callback, void *param)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->source) {
    return;
  }

  std::vector<obs_source_t *> children;
  auto capture = snapshot_live_capture(context);
  if (capture.source && capture.window_id != 0) {
    children.push_back(capture.source);
    capture.source = nullptr;
  }
  release_live_capture_snapshot(capture);

  auto audio = snapshot_live_audio(context);
  if (audio.source) {
    children.push_back(audio.source);
    audio.source = nullptr;
  }
  release_live_audio_snapshot(audio);

  {
    std::lock_guard<std::mutex> lock(context->media_mutex);
    for (const auto &media : context->media_playback) {
      if (media.source) {
        if (obs_source_t *child = obs_source_get_ref(media.source)) {
          children.push_back(child);
        }
      }
    }
  }

  for (obs_source_t *child : children) {
    enum_callback(context->source, child, param);
    obs_source_release(child);
  }
}

obs_source_info *pptbridge_slide_source_info()
{
  static obs_source_info info = {};
  info.id = "pptbridge_slide_source";
  info.type = OBS_SOURCE_TYPE_INPUT;
  info.output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_AUDIO | OBS_SOURCE_CUSTOM_DRAW;
  info.get_name = slide_source_get_name;
  info.create = slide_source_create;
  info.destroy = slide_source_destroy;
  info.get_defaults = slide_source_defaults;
  info.get_properties = slide_source_get_properties;
  info.update = slide_source_update;
  info.activate = slide_source_activate;
  info.deactivate = slide_source_deactivate;
  info.video_tick = slide_source_video_tick;
  info.video_render = slide_source_video_render;
  info.audio_render = slide_source_audio_render;
  info.get_width = slide_source_get_width;
  info.get_height = slide_source_get_height;
  info.enum_active_sources = slide_source_enum_active_sources;
  info.enum_all_sources = slide_source_enum_all_sources;
  return &info;
}

}  // namespace pptbridge
