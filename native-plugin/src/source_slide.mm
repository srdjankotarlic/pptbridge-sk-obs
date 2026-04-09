#import "source_shared.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#include <cmath>
#include <functional>
#include <sstream>
#include <obs-frontend-api.h>

#include "pptbridge_registry.hpp"

namespace pptbridge {

namespace {

constexpr const char *kHotkeyHelp =
  "Slide control:\n"
  "1. First launch default: key 2 = next slide, key 1 = previous slide\n"
  "2. Open Settings > Hotkeys\n"
  "3. Bind or change PPTBridge SK: Next Slide / Previous Slide\n"
  "4. For a clicker, use Right Arrow or Page Down for next, Left Arrow or Page Up for previous\n"
  "5. Use the buttons below for quick testing inside OBS";

constexpr const char *kMediaHelp =
  "Media note:\n"
  "In True Live PowerPoint Mode, PowerPoint itself drives builds, animations, video, and slide timing.\n"
  "If live mode is unavailable or disabled, PPTBridge falls back to legacy render mode with best-effort embedded media playback through OBS.";

constexpr const char *kLiveHelp =
  "True live mode:\n"
  "PowerPoint itself runs the slideshow, so click-build animations, embedded video, and slide timing behave like real PowerPoint.\n"
  "Recommended for macOS when Microsoft PowerPoint is installed.";

constexpr const char *kAudioHelp =
  "Conference audio:\n"
  "Audio from the PowerPoint slideshow is routed into the PPTBridge SK Slide source when available.\n"
  "OBS controls this audio in the Audio Mixer, not inside the video frame.\n"
  "In Studio Mode, the PPTBridge source currently active in Program is the one that should drive audio.\n"
  "For the cleanest live workflow, reuse one existing PPTBridge SK Slide source across scenes instead of making multiple copies of the same deck.";

constexpr auto kLiveRecoverRetryDelay = std::chrono::seconds(3);
constexpr auto kLiveReloadDelay = std::chrono::seconds(10);

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

struct LiveAudioTarget {
  std::string bundle_id;
  std::string application_name;
  int pid = 0;
};

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
      obs_source_release(media.source);
      media.source = nullptr;
    }
  }
}

void sync_media_playback_activity(SourceContext *context)
{
  if (!context || context->mode != ViewMode::Slide) {
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
    (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
  if (!windows) {
    return kCGNullWindowID;
  }

  NSString *target_title = window_title.empty() ? nil : [NSString stringWithUTF8String:window_title.c_str()];
  NSString *deck_name_ns = deck_name.empty() ? nil : [NSString stringWithUTF8String:deck_name.c_str()];
  NSString *deck_stem = deck_name_ns ? [[deck_name_ns lastPathComponent] stringByDeletingPathExtension] : nil;

  CGWindowID matched_id = kCGNullWindowID;
  CGWindowID fallback_id = kCGNullWindowID;
  for (NSDictionary *window in windows) {
    NSString *owner_name = [window objectForKey:(NSString *)kCGWindowOwnerName];
    NSString *name = [window objectForKey:(NSString *)kCGWindowName];
    NSNumber *window_id = [window objectForKey:(NSString *)kCGWindowNumber];

    if (!owner_name || !name || !window_id) {
      continue;
    }

    const std::string owner = owner_name.UTF8String ? owner_name.UTF8String : "";
    const std::string title = name.UTF8String ? name.UTF8String : "";
    if (owner != "Microsoft PowerPoint") {
      continue;
    }

    if (target_title && [name isEqualToString:target_title]) {
      matched_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
      break;
    }

    if (deck_stem && [name localizedCaseInsensitiveContainsString:deck_stem]) {
      fallback_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
    } else if (!fallback_id && [name localizedCaseInsensitiveContainsString:@"PowerPoint Slide Show"]) {
      fallback_id = static_cast<CGWindowID>(window_id.unsignedIntValue);
    }
  }

  return matched_id != kCGNullWindowID ? matched_id : fallback_id;
}

void set_live_capture_active(SourceContext *context, bool should_be_showing, bool should_be_active)
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

void set_live_audio_active(SourceContext *context, bool should_be_showing, bool should_be_active)
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

void clear_live_capture_source(SourceContext *context)
{
  if (!context) {
    return;
  }

  set_live_capture_active(context, false, false);
  if (context->live_capture_source) {
    obs_source_release(context->live_capture_source);
    context->live_capture_source = nullptr;
  }
  context->live_capture_window_id = 0;
  context->live_capture_window_title.clear();
}

void clear_live_audio_source(SourceContext *context)
{
  if (!context) {
    return;
  }

  set_live_audio_active(context, false, false);
  if (context->live_audio_source) {
    obs_source_release(context->live_audio_source);
    context->live_audio_source = nullptr;
  }
  context->live_audio_owner_pid = 0;
  context->live_audio_application.clear();
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
  if (!context || !context->live_capture_source) {
    return;
  }

  const bool should_be_active = context->source && obs_source_active(context->source);
  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || should_be_active);
  set_live_capture_active(context, should_be_showing, should_be_active);
}

void sync_live_audio_activity(SourceContext *context)
{
  if (!context || !context->live_audio_source) {
    return;
  }

  const bool should_be_active = context->source && obs_source_active(context->source);
  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || should_be_active);
  set_live_audio_active(context, should_be_showing, should_be_active);
}

void sync_live_capture_source(SourceContext *context)
{
  if (!context || context->mode != ViewMode::Slide || !context->document || !context->use_live_powerpoint) {
    clear_live_capture_source(context);
    return;
  }

  if (!context->document->IsLivePowerPointReady()) {
    clear_live_capture_source(context);
    return;
  }

  const auto window_title = context->document->LiveWindowTitle();
  const auto window_id = static_cast<uint32_t>(find_powerpoint_window_id(window_title, context->document->Name()));
  if (window_id == 0) {
    if (context->live_capture_source && context->live_capture_window_title == window_title) {
      sync_live_capture_activity(context);
      return;
    }
    clear_live_capture_source(context);
    return;
  }

  if (context->live_capture_source &&
      context->live_capture_window_id == window_id &&
      context->live_capture_window_title == window_title) {
    sync_live_capture_activity(context);
    return;
  }

  clear_live_capture_source(context);
  context->live_capture_source = create_live_capture_source(context, window_id, window_title);
  context->live_capture_window_id = window_id;
  context->live_capture_window_title = window_title;
  sync_live_capture_activity(context);
}

void sync_live_audio_source(SourceContext *context)
{
  if (!context || context->mode != ViewMode::Slide || !context->document || !context->use_live_powerpoint ||
      !context->use_live_app_audio || !context->audio_enabled) {
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

  if (context->live_audio_source &&
      context->live_audio_owner_pid == target.pid &&
      context->live_audio_application == target.application_name) {
    sync_live_audio_activity(context);
    return;
  }

  clear_live_audio_source(context);
  context->live_audio_source = create_live_audio_source(context, target);
  context->live_audio_owner_pid = target.pid;
  context->live_audio_application = target.application_name;
  sync_live_audio_activity(context);
}

bool render_live_capture(SourceContext *context)
{
  if (!context || !context->live_capture_source || !context->document || context->document->IsBlackScreen()) {
    return false;
  }

  const uint32_t capture_width = obs_source_get_width(context->live_capture_source);
  const uint32_t capture_height = obs_source_get_height(context->live_capture_source);
  if (capture_width == 0 || capture_height == 0) {
    return false;
  }

  gs_matrix_push();
  gs_matrix_scale3f(
    static_cast<float>(context->width) / static_cast<float>(capture_width),
    static_cast<float>(context->height) / static_cast<float>(capture_height),
    1.0f);
  obs_source_video_render(context->live_capture_source);
  gs_matrix_pop();
  return true;
}

std::vector<ChildAudioSnapshot> snapshot_audio_children(SourceContext *context)
{
  std::vector<ChildAudioSnapshot> snapshot;
  if (!context) {
    return snapshot;
  }

  if (context->live_capture_source) {
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
  playback.is_audio = true;
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
  obs_data_set_bool(settings, "restart_on_activate", false);
  obs_data_set_bool(settings, "close_when_inactive", true);
  obs_data_set_bool(settings, "clear_on_media_end", false);
  obs_data_set_bool(settings, "hw_decode", true);

  std::string name = std::string(obs_source_get_name(context->source)) + " Media " + std::to_string(index + 1);
  playback.source = obs_source_create_private("ffmpeg_source", name.c_str(), settings);
  obs_data_release(settings);

  if (!playback.source) {
    blog(
      LOG_WARNING,
      "[PPTBridge] Could not create ffmpeg media child for '%s'",
      media.file_path.c_str());
  }

  return playback;
}

void sync_media_sources(SourceContext *context)
{
  if (!context || context->mode != ViewMode::Slide) {
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
  if (!context || context->mode != ViewMode::Slide || !context->document || context->document->IsBlackScreen()) {
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

  status << "Presentation: " << context->document->Name() << "\n";
  status << "Mode: " << (live_enabled ? "True Live PowerPoint" : "Legacy Render") << "\n";
  status << "Load state: "
         << (loading ? "loading" : (live_ready ? "live ready" : (loaded ? "ready" : "idle"))) << "\n";
  status << "Slide: " << current_slide << " / " << slide_count << "\n";

  const auto kind = context->mode == ViewMode::Slide ? RegisteredSourceKind::Slide : RegisteredSourceKind::Presenter;
  const auto matching_sources = Registry::Instance().CountSources(context->pptx_path, kind);
  status << "Matching "
         << (context->mode == ViewMode::Slide ? "slide" : "presenter")
         << " sources for this deck: " << matching_sources << "\n";

  if (live_enabled) {
    status << "Live window: ";
    if (!context->live_capture_window_title.empty()) {
      status << context->live_capture_window_title;
    } else if (!context->document->LiveWindowTitle().empty()) {
      status << context->document->LiveWindowTitle();
    } else {
      status << "waiting";
    }
    status << "\n";

    status << "Live capture: ";
    if (context->live_capture_source) {
      status << "attached";
    } else if (live_ready) {
      status << "searching for slideshow window";
    } else {
      status << "not ready";
    }
    status << "\n";
    status << "Auto recover: " << (context->auto_recover_live ? "enabled" : "manual only") << "\n";
  }

  status << "Audio: "
         << (context->audio_enabled ? "enabled" : "muted")
         << ", gain " << context->audio_gain_db << " dB";
  if (context->mode == ViewMode::Slide) {
    status << "\nPowerPoint app audio: ";
    if (!context->use_live_app_audio) {
      status << "disabled";
    } else if (!live_enabled) {
      status << "available in true live mode";
    } else if (context->live_audio_source) {
      status << "attached";
      if (!context->live_audio_application.empty()) {
        status << " (" << context->live_audio_application << ")";
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

bool control_reattach_live(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context) {
    return false;
  }

  clear_live_capture_source(context);
  clear_live_audio_source(context);
  if (context->document) {
    Registry::Instance().SetActive(context->document);
    context->document->SyncLiveStateAsync();
  }
  return false;
}

}  // namespace

void source_defaults(obs_data_t *settings)
{
  obs_data_set_default_string(settings, "pptx_path", "");
  obs_data_set_default_int(settings, "canvas_width", 1920);
  obs_data_set_default_int(settings, "canvas_height", 1080);
  obs_data_set_default_bool(settings, "use_live_powerpoint", true);
  obs_data_set_default_bool(settings, "audio_enabled", true);
  obs_data_set_default_bool(settings, "use_live_app_audio", true);
  obs_data_set_default_bool(settings, "auto_recover_live", true);
  obs_data_set_default_double(settings, "audio_gain_db", 0.0);
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
  if (context && context->mode == ViewMode::Slide) {
    obs_properties_add_bool(props, "use_live_powerpoint", "Use True Live PowerPoint Mode");
    obs_properties_add_bool(props, "audio_enabled", "Enable PPTBridge Audio Output");
    obs_properties_add_bool(props, "use_live_app_audio", "Route PowerPoint App Audio Through OBS");
    obs_properties_add_bool(props, "auto_recover_live", "Auto Recover Live PowerPoint Session");
    obs_properties_add_float_slider(props, "audio_gain_db", "Audio Gain (dB)", -30.0, 18.0, 0.5);
  }

  const std::string status_text = build_status_text(context);
  obs_property_t *status = obs_properties_add_text(props, "pptbridge_status", status_text.c_str(), OBS_TEXT_INFO);
  obs_property_text_set_info_type(status, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(status, true);

  obs_property_t *help = obs_properties_add_text(props, "pptbridge_help", kHotkeyHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(help, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(help, true);

  obs_property_t *live_help = obs_properties_add_text(props, "pptbridge_live_help", kLiveHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(live_help, OBS_TEXT_INFO_NORMAL);
  obs_property_text_set_info_word_wrap(live_help, true);

  obs_property_t *media_help = obs_properties_add_text(props, "pptbridge_media_help", kMediaHelp, OBS_TEXT_INFO);
  obs_property_text_set_info_type(media_help, OBS_TEXT_INFO_WARNING);
  obs_property_text_set_info_word_wrap(media_help, true);

  if (context && context->mode == ViewMode::Slide) {
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
  if (context && context->mode == ViewMode::Slide) {
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
  const uint32_t width = static_cast<uint32_t>(obs_data_get_int(settings, "canvas_width"));
  const uint32_t height = static_cast<uint32_t>(obs_data_get_int(settings, "canvas_height"));
  const bool use_live_powerpoint = obs_data_get_bool(settings, "use_live_powerpoint");
  const bool audio_enabled = obs_data_get_bool(settings, "audio_enabled");
  const bool use_live_app_audio = obs_data_get_bool(settings, "use_live_app_audio");
  const bool auto_recover_live = obs_data_get_bool(settings, "auto_recover_live");
  const double audio_gain_db = obs_data_get_double(settings, "audio_gain_db");

  const bool path_changed = context->pptx_path != (path ? path : "");
  const bool size_changed = context->width != width || context->height != height;
  const bool live_mode_changed = context->use_live_powerpoint != use_live_powerpoint;
  const bool live_audio_mode_changed = context->use_live_app_audio != use_live_app_audio;

  context->pptx_path = path ? path : "";
  context->width = width;
  context->height = height;
  context->use_live_powerpoint = use_live_powerpoint;
  context->audio_enabled = audio_enabled;
  context->use_live_app_audio = use_live_app_audio;
  context->auto_recover_live = auto_recover_live;
  context->audio_gain_db = audio_gain_db;

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
    clear_live_capture_source(context);
    clear_live_audio_source(context);
    context->document.reset();
    if (!context->pptx_path.empty()) {
      context->document = Registry::Instance().Acquire(context->pptx_path);
    }
    if (context->document) {
      if (context->mode == ViewMode::Slide) {
        context->document->SetLivePowerPointEnabled(context->use_live_powerpoint);
      }
      if (context->mode == ViewMode::Presenter) {
        context->document->SetPresenterAssetsWanted(true);
      }
      context->document->EnsureLoadingAsync();
      Registry::Instance().SetActive(context->document);
    }
  } else if (live_audio_mode_changed) {
    clear_live_audio_source(context);
  } else if (context->document) {
    if (context->mode == ViewMode::Slide) {
      context->document->SetLivePowerPointEnabled(context->use_live_powerpoint);
    }
    if (context->mode == ViewMode::Presenter) {
      context->document->SetPresenterAssetsWanted(true);
    }
  }

  if (path_changed || size_changed || live_mode_changed) {
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

  if (!context || context->mode != ViewMode::Slide || !context->document) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (context->live_capture_source) {
    context->live_capture_last_seen = now;
  }
  if (context->live_audio_source) {
    context->live_audio_last_seen = now;
  }

  const bool should_watchdog =
    context->auto_recover_live &&
    context->use_live_powerpoint &&
    context->document->IsLivePowerPointEnabled() &&
    context->document->IsLivePowerPointReady() &&
    context->source &&
    (obs_source_showing(context->source) || obs_source_active(context->source));

  if (!should_watchdog) {
    return;
  }

  if (!context->live_capture_source &&
      now - context->live_capture_last_seen >= kLiveRecoverRetryDelay &&
      (context->live_recover_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_recover_last_attempt >= kLiveRecoverRetryDelay)) {
    blog(LOG_WARNING, "[PPTBridge SK] Live slideshow capture missing; attempting automatic reattach");
    context->live_recover_last_attempt = now;
    clear_live_capture_source(context);
    clear_live_audio_source(context);
    context->document->SyncLiveStateAsync();
  }

  if (!context->live_capture_source &&
      now - context->live_capture_last_seen >= kLiveReloadDelay &&
      (context->live_reload_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_reload_last_attempt >= kLiveReloadDelay)) {
    blog(LOG_WARNING, "[PPTBridge SK] Live slideshow capture did not recover; reloading presentation session");
    context->live_reload_last_attempt = now;
    context->document->ReloadAsync();
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

  if (render_live_capture(context)) {
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
  Registry::Instance().DetachSource(context);
  clear_live_capture_source(context);
  clear_live_audio_source(context);
  clear_media_sources(context);
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
  if (!context->audio_enabled) {
    return false;
  }

  const float gain = audio_gain_multiplier_db(context->audio_gain_db);

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
    return false;
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

      for (size_t channel = 0; channel < channels; ++channel) {
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

  std::lock_guard<std::mutex> lock(context->media_mutex);
  if (context->live_capture_source && context->live_capture_active) {
    enum_callback(context->source, context->live_capture_source, param);
  }
  if (context->live_audio_source && context->live_audio_active) {
    enum_callback(context->source, context->live_audio_source, param);
  }
  for (const auto &media : context->media_playback) {
    if (media.source && media.active_child) {
      enum_callback(context->source, media.source, param);
    }
  }
}

static void slide_source_enum_all_sources(void *data, obs_source_enum_proc_t enum_callback, void *param)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->source) {
    return;
  }

  std::lock_guard<std::mutex> lock(context->media_mutex);
  if (context->live_capture_source) {
    enum_callback(context->source, context->live_capture_source, param);
  }
  if (context->live_audio_source) {
    enum_callback(context->source, context->live_audio_source, param);
  }
  for (const auto &media : context->media_playback) {
    if (media.source) {
      enum_callback(context->source, media.source, param);
    }
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
