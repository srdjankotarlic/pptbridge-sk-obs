#include "source_shared.hpp"

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <callback/calldata.h>
#include <callback/proc.h>
#include <cctype>
#include <chrono>
#include <cstring>
#include <cmath>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <obs-frontend-api.h>
#include <sstream>
#include <string>
#include <utility>
#include <util/platform.h>
#include <vector>

#include "pptbridge_osc_server.hpp"
#include "pptbridge_registry.hpp"

namespace pptbridge {

namespace {

constexpr const char *kHotkeyHelp =
  "Slide control:\n"
  "1. First launch default while OBS is focused: key 2 or Right Arrow = next slide, key 1 or Left Arrow = previous slide\n"
  "2. Open Settings > Hotkeys\n"
  "3. Bind or change PPTBridge SK: Next Slide / Previous Slide; add PageDown/PageUp there if those keys only need to work while OBS is focused\n"
  "4. PPTBridge only acts on hotkeys while OBS is the active app, so typing in another window will not move slides\n"
  "5. For a stage clicker while you use Chrome, OBS, or another app, enable Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off; it uses PageDown/Right and PageUp/Left, not Space\n"
  "6. Use one scene per deck for multi-deck shows; hotkeys, clicker capture, and OSC follow the current OBS Program scene\n"
  "7. Use the buttons below for quick testing inside OBS";

constexpr const char *kMediaHelp =
  "Windows playback note:\n"
  "PPTBridge SK for Windows prefers a real PowerPoint slideshow session and then attaches OBS to that live show when possible.\n"
  "If the live slideshow window is not available yet, PPTBridge falls back to exported slides plus extracted embedded media so your show stays controllable inside OBS.";

constexpr const char *kLiveHelp =
  "True live mode on Windows:\n"
  "PowerPoint itself drives the slideshow, while PPTBridge keeps OBS in sync and attempts to attach the live slideshow window as an OBS source.\n"
  "That is the path we need for real animations, embedded video, and click-build behavior.";

constexpr const char *kLiveControlHelp =
  "Main PowerPoint live controls:\n"
  "Start / Restart opens PowerPoint if needed, begins the live slideshow, and recovers the deck if the slideshow window was closed.\n"
  "Stop ends the PowerPoint live slideshow without quitting OBS.";

constexpr const char *kPresenterLiveControlHelp =
  "Presenter live controls:\n"
  "Start / Restart opens the same PowerPoint live slideshow used by PPTBridge SK Slide and recovers it if the slideshow window was closed.\n"
  "For the audience/program feed, add PPTBridge SK Slide to the OBS Program scene.";

constexpr const char *kLiveResizeHelp =
  "PowerPoint window resize:\n"
  "Lock OBS Output Size keeps the PPTBridge source filling the OBS canvas even if you shrink or resize the PowerPoint slideshow window.\n"
  "Use Follow PowerPoint Window only when you intentionally want the OBS output to reflect the current PowerPoint window shape.";

constexpr const char *kAudioHelp =
  "Conference audio on Windows:\n"
  "PPTBridge first tries to use OBS window capture audio for the PowerPoint slideshow window itself, because that keeps the live show path tighter.\n"
  "If that path is not ready yet, PPTBridge can still try a dedicated PowerPoint process-audio path as a fallback.";

constexpr auto kLiveRecoverRetryDelay = std::chrono::seconds(3);
constexpr auto kLiveReloadDelay = std::chrono::seconds(12);
constexpr auto kLiveSyncIntervalActive = std::chrono::milliseconds(250);
constexpr auto kLiveSyncIntervalIdle = std::chrono::seconds(1);
constexpr int kWindowCaptureMethodBitBlt = 1;
constexpr int kWindowPriorityClass = 0;
constexpr int kWindowPriorityTitle = 1;

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

struct LiveWindowTarget {
  HWND hwnd = nullptr;
  uint32_t pid = 0;
  std::string title;
  std::string class_name;
  std::string executable_name;
  std::string descriptor;
};

struct HookedSourceState {
  bool hooked = false;
  std::string title;
  std::string class_name;
  std::string executable;
};

std::wstring Utf8ToWide(const std::string &value)
{
  if (value.empty()) {
    return {};
  }

  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 1) {
    return {};
  }

  std::wstring wide(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), size);
  return wide;
}

std::string WideToUtf8(const std::wstring &value)
{
  if (value.empty()) {
    return {};
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return {};
  }

  std::string utf8(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::string ToLowerCopy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
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

std::string sanitize_descriptor_value(std::string value)
{
  size_t position = 0;
  while ((position = value.find('#', position)) != std::string::npos) {
    value.replace(position, 1, "#22");
    position += 3;
  }

  position = 0;
  while ((position = value.find(':', position)) != std::string::npos) {
    value.replace(position, 1, "#3A");
    position += 3;
  }
  return value;
}

std::string get_window_text_utf8(HWND hwnd)
{
  const int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) {
    return {};
  }

  std::wstring title(static_cast<size_t>(length + 1), L'\0');
  GetWindowTextW(hwnd, title.data(), static_cast<int>(title.size()));
  title.resize(std::wcslen(title.c_str()));
  return WideToUtf8(title);
}

std::string get_class_name_utf8(HWND hwnd)
{
  wchar_t class_name[256] = {};
  const int length = GetClassNameW(hwnd, class_name, 255);
  if (length <= 0) {
    return {};
  }
  return WideToUtf8(std::wstring(class_name, class_name + length));
}

std::string get_process_executable_name(uint32_t pid)
{
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    return {};
  }

  wchar_t path[MAX_PATH * 4] = {};
  DWORD size = static_cast<DWORD>(std::size(path));
  std::string name;
  if (QueryFullProcessImageNameW(process, 0, path, &size)) {
    name = WideToUtf8(std::wstring(path, path + size));
  }
  CloseHandle(process);

  if (name.empty()) {
    return {};
  }

  const auto separator = name.find_last_of("\\/");
  return separator == std::string::npos ? name : name.substr(separator + 1);
}

struct WindowSearchContext {
  std::string preferred_title;
  std::string deck_name;
  std::string deck_stem;
  LiveWindowTarget result;
  int best_score = 0;
};

std::string filename_stem_for_match(std::string value)
{
  const auto separator = value.find_last_of("\\/");
  if (separator != std::string::npos) {
    value = value.substr(separator + 1);
  }

  const auto dot = value.find_last_of('.');
  if (dot != std::string::npos) {
    value = value.substr(0, dot);
  }
  return value;
}

bool looks_like_powerpoint_slideshow_title(const std::string &title_lower)
{
  return title_lower.find("slide show") != std::string::npos ||
         title_lower.find("slideshow") != std::string::npos ||
         title_lower.find("bildschirm") != std::string::npos ||
         title_lower.find("diaporama") != std::string::npos;
}

BOOL CALLBACK enum_powerpoint_windows(HWND hwnd, LPARAM param)
{
  auto *context = reinterpret_cast<WindowSearchContext *>(param);
  if (!context || !IsWindowVisible(hwnd)) {
    return TRUE;
  }

  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0) {
    return TRUE;
  }

  const auto executable = ToLowerCopy(get_process_executable_name(pid));
  if (executable != "powerpnt.exe") {
    return TRUE;
  }

  const auto title = get_window_text_utf8(hwnd);
  if (title.empty()) {
    return TRUE;
  }

  const auto class_name = get_class_name_utf8(hwnd);
  const auto class_lower = ToLowerCopy(class_name);
  const auto title_lower = ToLowerCopy(title);
  const auto preferred_lower = ToLowerCopy(context->preferred_title);
  const auto deck_lower = ToLowerCopy(context->deck_name);
  const auto deck_stem_lower = ToLowerCopy(context->deck_stem);
  const bool is_screen_class = class_lower == "screenclass";
  const bool looks_like_slideshow = looks_like_powerpoint_slideshow_title(title_lower);

  int score = 0;
  if (is_screen_class) {
    score += 200;
  } else if (class_lower == "pptframeclass") {
    score += 40;
  }
  if (!preferred_lower.empty() && title_lower.find(preferred_lower) != std::string::npos) {
    score += 100;
  }
  if (!deck_lower.empty() && title_lower.find(deck_lower) != std::string::npos) {
    score += 90;
  }
  if (!deck_stem_lower.empty() && title_lower.find(deck_stem_lower) != std::string::npos) {
    score += 85;
  }
  if (looks_like_slideshow) {
    score += 65;
  }

  if (score <= 0 || (!is_screen_class && !looks_like_slideshow)) {
    return TRUE;
  }

  if (score <= context->best_score) {
    return TRUE;
  }

  context->best_score = score;
  context->result.hwnd = hwnd;
  context->result.pid = pid;
  context->result.title = title;
  context->result.class_name = class_name;
  context->result.executable_name = "POWERPNT.EXE";
  context->result.descriptor = sanitize_descriptor_value(title) + ":" +
    sanitize_descriptor_value(context->result.class_name) + ":" +
    sanitize_descriptor_value(context->result.executable_name);
  return TRUE;
}

LiveWindowTarget find_powerpoint_window(const std::string &window_title, const std::string &deck_name)
{
  WindowSearchContext search = {};
  search.preferred_title = window_title;
  search.deck_name = deck_name;
  search.deck_stem = filename_stem_for_match(deck_name);
  EnumWindows(enum_powerpoint_windows, reinterpret_cast<LPARAM>(&search));
  return search.result;
}

void start_media_playback(obs_source_t *source)
{
  if (!source) {
    return;
  }

  obs_source_media_stop(source);
  obs_source_media_restart(source);
}

bool has_case_insensitive_extension(const std::string &path, const char *extension)
{
  if (!extension) {
    return false;
  }
  const size_t extension_len = std::strlen(extension);
  if (path.size() < extension_len) {
    return false;
  }
  const std::string actual = path.substr(path.size() - extension_len);
  for (size_t i = 0; i < extension_len; ++i) {
    if (std::tolower(static_cast<unsigned char>(actual[i])) !=
        std::tolower(static_cast<unsigned char>(extension[i]))) {
      return false;
    }
  }
  return true;
}

uint16_t read_le16(const uint8_t *data)
{
  return static_cast<uint16_t>(data[0]) |
         static_cast<uint16_t>(data[1] << 8);
}

uint32_t read_le32(const uint8_t *data)
{
  return static_cast<uint32_t>(data[0]) |
         (static_cast<uint32_t>(data[1]) << 8) |
         (static_cast<uint32_t>(data[2]) << 16) |
         (static_cast<uint32_t>(data[3]) << 24);
}

bool load_wav_file(const std::string &path, std::vector<float> &samples, uint32_t &channels, uint32_t &sample_rate)
{
  samples.clear();
  channels = 0;
  sample_rate = 0;

  std::ifstream file(path, std::ios::binary);
  if (!file) {
    return false;
  }

  uint8_t riff[12] = {};
  file.read(reinterpret_cast<char *>(riff), sizeof(riff));
  if (file.gcount() != sizeof(riff) ||
      std::memcmp(riff, "RIFF", 4) != 0 ||
      std::memcmp(riff + 8, "WAVE", 4) != 0) {
    return false;
  }

  uint16_t audio_format = 0;
  uint16_t bits_per_sample = 0;
  uint16_t block_align = 0;
  std::vector<uint8_t> data_chunk;

  while (file) {
    uint8_t chunk_header[8] = {};
    file.read(reinterpret_cast<char *>(chunk_header), sizeof(chunk_header));
    if (file.gcount() != sizeof(chunk_header)) {
      break;
    }

    const uint32_t chunk_size = read_le32(chunk_header + 4);
    const std::streamoff next_chunk =
      static_cast<std::streamoff>(file.tellg()) + static_cast<std::streamoff>(chunk_size) +
      static_cast<std::streamoff>(chunk_size & 1u);

    if (std::memcmp(chunk_header, "fmt ", 4) == 0 && chunk_size >= 16) {
      std::vector<uint8_t> fmt(chunk_size);
      file.read(reinterpret_cast<char *>(fmt.data()), static_cast<std::streamsize>(fmt.size()));
      if (static_cast<uint32_t>(file.gcount()) < chunk_size) {
        return false;
      }
      audio_format = read_le16(fmt.data());
      channels = read_le16(fmt.data() + 2);
      sample_rate = read_le32(fmt.data() + 4);
      block_align = read_le16(fmt.data() + 12);
      bits_per_sample = read_le16(fmt.data() + 14);
    } else if (std::memcmp(chunk_header, "data", 4) == 0) {
      data_chunk.resize(chunk_size);
      if (chunk_size > 0) {
        file.read(reinterpret_cast<char *>(data_chunk.data()), static_cast<std::streamsize>(data_chunk.size()));
        if (static_cast<uint32_t>(file.gcount()) < chunk_size) {
          return false;
        }
      }
    }

    file.seekg(next_chunk, std::ios::beg);
  }

  if (channels == 0 || sample_rate == 0 || block_align == 0 || data_chunk.empty()) {
    return false;
  }
  if (audio_format != 1 && audio_format != 3) {
    return false;
  }

  const size_t frame_count = data_chunk.size() / block_align;
  if (frame_count == 0) {
    return false;
  }

  samples.resize(frame_count * channels);
  for (size_t frame = 0; frame < frame_count; ++frame) {
    const uint8_t *frame_data = data_chunk.data() + frame * block_align;
    for (uint32_t channel = 0; channel < channels; ++channel) {
      const uint8_t *sample_data = frame_data + channel * (bits_per_sample / 8);
      float value = 0.0f;
      if (audio_format == 1 && bits_per_sample == 8) {
        value = (static_cast<int>(sample_data[0]) - 128) / 128.0f;
      } else if (audio_format == 1 && bits_per_sample == 16) {
        const int16_t pcm = static_cast<int16_t>(read_le16(sample_data));
        value = static_cast<float>(pcm) / 32768.0f;
      } else if (audio_format == 1 && bits_per_sample == 24) {
        int32_t pcm = static_cast<int32_t>(sample_data[0]) |
                      (static_cast<int32_t>(sample_data[1]) << 8) |
                      (static_cast<int32_t>(sample_data[2]) << 16);
        if (pcm & 0x00800000) {
          pcm |= static_cast<int32_t>(0xFF000000);
        }
        value = static_cast<float>(pcm) / 8388608.0f;
      } else if (audio_format == 1 && bits_per_sample == 32) {
        const int32_t pcm = static_cast<int32_t>(read_le32(sample_data));
        value = static_cast<float>(pcm) / 2147483648.0f;
      } else if (audio_format == 3 && bits_per_sample == 32) {
        static_assert(sizeof(float) == sizeof(uint32_t), "float32 WAV support expects 32-bit float");
        uint32_t raw = read_le32(sample_data);
        std::memcpy(&value, &raw, sizeof(value));
        value = std::max(-1.0f, std::min(1.0f, value));
      } else {
        samples.clear();
        channels = 0;
        sample_rate = 0;
        return false;
      }
      samples[frame * channels + channel] = value;
    }
  }

  return true;
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
    if (!media.wav_samples.empty()) {
      media.wav_cursor = 0.0;
      media.wav_finished = false;
      media.wav_started = true;
    }
  }

  if (!should_be_active && media.active_child) {
    obs_source_remove_active_child(context->source, media.source);
    media.active_child = false;
  }

  if (!should_be_showing && media.showing_child) {
    obs_source_media_stop(media.source);
    obs_source_dec_showing(media.source);
    media.showing_child = false;
    media.wav_started = false;
    media.wav_finished = true;
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
    obs_source_inc_active(context->live_capture_source);
    context->live_capture_active = true;
  }

  if (!should_be_active && context->live_capture_active) {
    obs_source_dec_active(context->live_capture_source);
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
    obs_source_inc_active(context->live_audio_source);
    context->live_audio_active = true;
  }

  if (!should_be_active && context->live_audio_active) {
    obs_source_dec_active(context->live_audio_source);
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
  context->live_capture_hooked = false;
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
  context->live_audio_hooked = false;
}

HookedSourceState query_hooked_source_state(obs_source_t *source)
{
  HookedSourceState state;
  if (!source) {
    return state;
  }

  proc_handler_t *handler = obs_source_get_proc_handler(source);
  if (!handler) {
    return state;
  }

  calldata_t data;
  calldata_init(&data);
  const bool ok = proc_handler_call(handler, "get_hooked", &data);
  if (ok) {
    state.hooked = calldata_bool(&data, "hooked");
    if (const char *title = calldata_string(&data, "title")) {
      state.title = title;
    }
    if (const char *class_name = calldata_string(&data, "class")) {
      state.class_name = class_name;
    }
    if (const char *executable = calldata_string(&data, "executable")) {
      state.executable = executable;
    }
  }
  calldata_free(&data);
  return state;
}

void update_live_capture_hook_state(SourceContext *context)
{
  if (!context || !context->live_capture_source) {
    return;
  }

  const auto state = query_hooked_source_state(context->live_capture_source);
  if (state.hooked && !context->live_capture_hooked) {
    blog(
      LOG_INFO,
      "[PPTBridge SK] Windows live slideshow capture attached: title='%s', class='%s'",
      state.title.c_str(),
      state.class_name.c_str());
  }
  context->live_capture_hooked = state.hooked;
}

obs_source_t *create_live_capture_source(SourceContext *context, const LiveWindowTarget &target)
{
  if (!context || !context->source || target.descriptor.empty()) {
    return nullptr;
  }

  obs_data_t *settings = obs_data_create();
  obs_data_set_string(settings, "window", target.descriptor.c_str());
  obs_data_set_int(settings, "method", kWindowCaptureMethodBitBlt);
  obs_data_set_int(settings, "priority", kWindowPriorityClass);
  obs_data_set_bool(settings, "cursor", false);
  obs_data_set_bool(settings, "capture_audio", context->use_live_app_audio && context->audio_enabled);
  obs_data_set_bool(settings, "force_sdr", false);
  obs_data_set_bool(settings, "compatibility", false);
  obs_data_set_bool(settings, "client_area", false);

  std::string source_name = std::string(obs_source_get_name(context->source)) + " Live Capture";
  obs_source_t *capture = obs_source_create_private("window_capture", source_name.c_str(), settings);
  obs_data_release(settings);

  if (!capture) {
    blog(LOG_WARNING, "[PPTBridge SK] Could not create Windows PowerPoint live capture source");
  }

  return capture;
}

obs_source_t *create_live_audio_source(SourceContext *context, const LiveWindowTarget &target)
{
  if (!context || !context->source || target.descriptor.empty()) {
    return nullptr;
  }

  obs_data_t *settings = obs_data_create();
  obs_data_set_string(settings, "window", target.descriptor.c_str());
  obs_data_set_int(settings, "priority", kWindowPriorityTitle);

  std::string source_name = std::string(obs_source_get_name(context->source)) + " Live Audio";
  obs_source_t *audio = obs_source_create_private("wasapi_process_output_capture", source_name.c_str(), settings);
  obs_data_release(settings);

  if (!audio) {
    blog(LOG_WARNING, "[PPTBridge SK] Could not create Windows PowerPoint process audio source");
  }

  return audio;
}

void sync_live_capture_activity(SourceContext *context)
{
  if (!context || !context->live_capture_source) {
    return;
  }

  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || obs_source_active(context->source));
  const bool should_be_active = should_be_showing;
  set_live_capture_active(context, should_be_showing, should_be_active);
}

void sync_live_audio_activity(SourceContext *context)
{
  if (!context || !context->live_audio_source) {
    return;
  }

  const bool should_be_showing =
    context->source && (obs_source_showing(context->source) || obs_source_active(context->source));
  const bool should_be_active = should_be_showing;
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

  const auto target = find_powerpoint_window(context->document->LiveWindowTitle(), context->document->Name());
  if (!target.hwnd) {
    if (context->live_capture_source && !context->live_capture_window_title.empty()) {
      context->live_capture_hooked = query_hooked_source_state(context->live_capture_source).hooked;
      sync_live_capture_activity(context);
      return;
    }
    clear_live_capture_source(context);
    return;
  }

  if (context->live_capture_source &&
      context->live_capture_window_id == static_cast<uint64_t>(reinterpret_cast<uintptr_t>(target.hwnd)) &&
      context->live_capture_window_title == target.title) {
    const auto state = query_hooked_source_state(context->live_capture_source);
    context->live_capture_hooked = state.hooked;
    if (!state.title.empty()) {
      context->live_capture_window_title = state.title;
    }
    sync_live_capture_activity(context);
    return;
  }

  clear_live_capture_source(context);
  context->live_capture_source = create_live_capture_source(context, target);
  context->live_capture_window_id = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(target.hwnd));
  context->live_capture_window_title = target.title;
  context->live_capture_hooked = query_hooked_source_state(context->live_capture_source).hooked;
  blog(
    LOG_INFO,
    "[PPTBridge SK] Windows live slideshow target found: title='%s', class='%s', hooked=%s",
    target.title.c_str(),
    target.class_name.c_str(),
    context->live_capture_hooked ? "true" : "false");
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

  if (context->live_capture_source) {
    context->live_capture_hooked = query_hooked_source_state(context->live_capture_source).hooked;
  }

  if (context->live_capture_source && context->live_capture_hooked) {
    clear_live_audio_source(context);
    return;
  }

  const auto target = find_powerpoint_window(context->document->LiveWindowTitle(), context->document->Name());
  if (!target.hwnd) {
    clear_live_audio_source(context);
    return;
  }

  if (context->live_audio_source &&
      context->live_audio_owner_pid == static_cast<int>(target.pid) &&
      context->live_audio_application == target.executable_name) {
    context->live_audio_hooked = query_hooked_source_state(context->live_audio_source).hooked;
    sync_live_audio_activity(context);
    return;
  }

  clear_live_audio_source(context);
  context->live_audio_source = create_live_audio_source(context, target);
  context->live_audio_owner_pid = static_cast<int>(target.pid);
  context->live_audio_application = target.executable_name;
  context->live_audio_hooked = query_hooked_source_state(context->live_audio_source).hooked;
  sync_live_audio_activity(context);
}

bool render_live_capture(SourceContext *context)
{
  if (!context || !context->live_capture_source || !context->document || context->document->IsBlackScreen()) {
    return false;
  }

  update_live_capture_hook_state(context);

  const uint32_t capture_width = obs_source_get_width(context->live_capture_source);
  const uint32_t capture_height = obs_source_get_height(context->live_capture_source);
  if (capture_width == 0 || capture_height == 0) {
    return false;
  }

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
    ChildAudioSnapshot live_capture;
    live_capture.source = obs_source_get_ref(context->live_capture_source);
    live_capture.is_audio = true;
    if (live_capture.source) {
      snapshot.push_back(live_capture);
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

  if (playback.is_audio && has_case_insensitive_extension(media.file_path, ".wav")) {
    if (!load_wav_file(media.file_path, playback.wav_samples, playback.wav_channels, playback.wav_sample_rate)) {
      blog(LOG_WARNING, "[PPTBridge SK] Could not decode embedded WAV media '%s'", media.file_path.c_str());
    } else {
      playback.wav_started = true;
      playback.wav_finished = false;
      playback.wav_cursor = 0.0;
      blog(
        LOG_INFO,
        "[PPTBridge SK] Loaded embedded WAV fallback '%s' (%u Hz, %u channel(s), %zu frame(s))",
        media.file_path.c_str(),
        playback.wav_sample_rate,
        playback.wav_channels,
        playback.wav_channels ? playback.wav_samples.size() / playback.wav_channels : 0);
    }
  }

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
    blog(LOG_WARNING, "[PPTBridge SK] Could not create media child for '%s'", media.file_path.c_str());
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

  release_media_playback_snapshot(playback);
  if (!rendered_any) {
    return;
  }
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

bool mix_direct_wav_audio(
  SourceContext *context,
  struct obs_source_audio_mix *audio_output,
  uint32_t mixers,
  size_t channels,
  size_t sample_rate,
  float gain,
  uint64_t &timestamp_out)
{
  if (!context || !audio_output || channels == 0 || sample_rate == 0) {
    return false;
  }

  bool mixed_any = false;
  const uint32_t effective_mixers = mixers != 0 ? mixers : 0x1u;
  float push_left[AUDIO_OUTPUT_FRAMES] = {};
  float push_right[AUDIO_OUTPUT_FRAMES] = {};
  std::lock_guard<std::mutex> lock(context->media_mutex);
  for (auto &media : context->media_playback) {
    if (media.wav_samples.empty() || media.wav_channels == 0 || media.wav_sample_rate == 0 ||
        !media.wav_started || media.wav_finished) {
      continue;
    }

    const size_t total_frames = media.wav_samples.size() / media.wav_channels;
    if (total_frames == 0 || media.wav_cursor >= static_cast<double>(total_frames)) {
      media.wav_finished = true;
      continue;
    }

    const double step = static_cast<double>(media.wav_sample_rate) / static_cast<double>(sample_rate);
    bool mixed_media = false;

    for (size_t frame = 0; frame < AUDIO_OUTPUT_FRAMES; ++frame) {
      const size_t source_frame = static_cast<size_t>(media.wav_cursor);
      if (source_frame >= total_frames) {
        media.wav_finished = true;
        break;
      }

      for (size_t mix = 0; mix < MAX_AUDIO_MIXES; ++mix) {
        if ((effective_mixers & (1u << mix)) == 0) {
          continue;
        }

        for (size_t channel = 0; channel < channels; ++channel) {
          float *out = audio_output->output[mix].data[channel];
          if (!out) {
            continue;
          }
          const uint32_t source_channel = media.wav_channels == 1
            ? 0
            : static_cast<uint32_t>(std::min<size_t>(channel, media.wav_channels - 1));
          const float sample = media.wav_samples[source_frame * media.wav_channels + source_channel] * gain;
          out[frame] += sample;
          if (channel == 0) {
            push_left[frame] += sample;
          } else if (channel == 1) {
            push_right[frame] += sample;
          }
          mixed_media = true;
        }
      }

      media.wav_cursor += step;
    }

    mixed_any = mixed_any || mixed_media;
    if (mixed_media && !media.wav_mix_logged) {
      media.wav_mix_logged = true;
      blog(
        LOG_INFO,
        "[PPTBridge SK] Mixing embedded WAV fallback '%s' through OBS source audio",
        media.file_path.c_str());
    }
  }

  if (mixed_any) {
    timestamp_out = os_gettime_ns();
    if (context->source) {
      obs_source_audio audio = {};
      audio.data[0] = reinterpret_cast<const uint8_t *>(push_left);
      audio.data[1] = reinterpret_cast<const uint8_t *>(push_right);
      audio.frames = static_cast<uint32_t>(AUDIO_OUTPUT_FRAMES);
      audio.speakers = SPEAKERS_STEREO;
      audio.format = AUDIO_FORMAT_FLOAT_PLANAR;
      audio.samples_per_sec = static_cast<uint32_t>(sample_rate);
      audio.timestamp = timestamp_out;
      obs_source_output_audio(context->source, &audio);
    }
  }
  return mixed_any;
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

std::string describe_operator_status(const PresentationStatus &snapshot)
{
  std::ostringstream status;
  status << "Operator status: ";
  if (snapshot.total_slides == 0) {
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
  status << "\nLive: "
         << (snapshot.live_ready ? "PowerPoint attached" : (snapshot.live_enabled ? "waiting / cached fallback" : "cached PDF/PPT render"));
  if (snapshot.black_screen) {
    status << "\nBlack screen is ON";
  }
  return status.str();
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
    if (!context->live_capture_window_title.empty()) {
      status << context->live_capture_window_title;
    } else if (!context->document->LiveWindowTitle().empty()) {
      status << context->document->LiveWindowTitle();
    } else {
      status << "waiting";
    }
    status << "\n";

    if (context->mode == ViewMode::Slide) {
      status << "Live capture: ";
      if (context->live_capture_source && context->live_capture_hooked) {
        status << "attached";
      } else if (context->live_capture_source) {
        status << "created, waiting for hook";
      } else if (live_ready) {
        status << "searching for slideshow window";
      } else {
        status << "not ready";
      }
      status << "\n";
    } else {
      status << "Presenter live sync: " << (live_ready ? "following PowerPoint slideshow" : "waiting for live slideshow") << "\n";
    }

    if (context->mode == ViewMode::Slide) {
      status << "PowerPoint app audio: ";
      if (!context->use_live_app_audio) {
        status << "disabled";
      } else if (context->live_capture_source && context->live_capture_hooked) {
        status << "attached through live window capture";
      } else if (context->live_audio_source && context->live_audio_hooked) {
        status << "attached through process audio fallback";
      } else if (context->live_audio_source) {
        status << "created, waiting for process hook";
      } else if (live_ready) {
        status << "searching for process audio";
      } else {
        status << "not ready";
      }
      status << "\n";
    }
    if (context->mode == ViewMode::Slide) {
      status << "Auto recover: " << (context->auto_recover_live ? "enabled" : "manual only") << "\n";
      status << "PowerPoint resize: "
             << (context->live_capture_resize_mode == LiveCaptureResizeMode::FitWindow
                   ? "following PowerPoint window"
                   : "locked to OBS canvas")
             << "\n";
    }
  }

  if (context->mode == ViewMode::Slide) {
    status << "Audio: " << (context->audio_enabled ? "enabled" : "muted")
           << ", gain " << context->audio_gain_db << " dB";
  } else {
    status << "Presenter output: current slide, next slide, notes, and timer";
    if (!context->cue_export_status.empty()) {
      status << "\nCue list: " << context->cue_export_status;
    }
  }

  if (matching_sources > 1) {
    status << "\nWarning: multiple "
           << (context->mode == ViewMode::Slide ? "slide" : "presenter")
           << " sources point to this same deck. Use Add Existing when you want one shared source instance.";
  }

  if (!last_error.empty()) {
    status << "\nLast issue: " << last_error;
  }
  if (context->osc_feedback_enabled) {
    status << "\nOSC feedback: " << context->osc_feedback_host << ":" << context->osc_feedback_port;
    if (!context->osc_feedback_status.empty()) {
      status << " (" << context->osc_feedback_status << ")";
    }
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

bool control_start_live(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context) {
    return false;
  }

  if (context->source && !context->use_live_powerpoint) {
    obs_data_t *settings = obs_source_get_settings(context->source);
    if (settings) {
      obs_data_set_bool(settings, "use_live_powerpoint", true);
      obs_source_update(context->source, settings);
      obs_data_release(settings);
    }
  }

  if (!context->document) {
    return false;
  }

  Registry::Instance().SetActive(context->document);
  clear_live_capture_source(context);
  clear_live_audio_source(context);
  context->document->SetLivePowerPointEnabled(true);
  context->document->StartLivePowerPointAsync();
  return false;
}

bool control_stop_live(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return false;
  }

  clear_live_capture_source(context);
  clear_live_audio_source(context);
  context->document->StopLivePowerPointAsync();
  return false;
}

bool control_export_cue_list(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return false;
  }

  std::string output_path;
  std::string error;
  if (context->document->ExportCueList(output_path, error)) {
    context->cue_export_status = "exported to " + output_path;
    blog(LOG_INFO, "[PPTBridge SK] Exported cue list to '%s'", output_path.c_str());
  } else {
    context->cue_export_status = error.empty() ? "export failed" : error;
    blog(LOG_WARNING, "[PPTBridge SK] Could not export cue list: %s", context->cue_export_status.c_str());
  }
  return true;
}

bool control_toggle_current_cue(obs_properties_t *, obs_property_t *, void *data)
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
  return true;
}

bool control_toggle_next_cue(obs_properties_t *, obs_property_t *, void *data)
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
  return true;
}

bool control_clear_cue_checks(obs_properties_t *, obs_property_t *, void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  if (!context || !context->document) {
    return true;
  }

  context->document->ClearCueChecks();
  context->cue_export_status = "cleared cue checks";
  send_osc_status(context, true);
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

void add_operator_mode_properties(obs_properties_t *props, SourceContext *context)
{
  obs_properties_t *operator_props = obs_properties_create();
  PresentationStatus snapshot;
  if (context && context->document) {
    snapshot = context->document->SnapshotStatus();
  }

  obs_property_t *operator_help = obs_properties_add_text(
    operator_props,
    "pptbridge_operator_help",
    "Use this panel during the show: start live mode if needed, move slides, mark cues, and send Companion/OSC status.",
    OBS_TEXT_INFO);
  obs_property_text_set_info_type(operator_help, OBS_TEXT_INFO_WARNING);
  obs_property_text_set_info_word_wrap(operator_help, true);

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

  const std::string operator_status = describe_operator_status(snapshot);
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
  obs_properties_add_path(
    props,
    "pptx_path",
    "Presentation File",
    OBS_PATH_FILE,
    "PowerPoint (*.ppt *.pptx *.pptm *.ppsx *.potx *.potm)",
    nullptr);
  add_operator_mode_properties(props, context);
  if (context && context->mode == ViewMode::Presenter) {
    obs_properties_add_int(props, "canvas_width", "Canvas Width", 320, 7680, 1);
    obs_properties_add_int(props, "canvas_height", "Canvas Height", 240, 4320, 1);
    add_presenter_customization_properties(props);
    obs_properties_add_button(props, "pptbridge_export_cue_list_btn", "Export Cue List (.txt)", control_export_cue_list);

    obs_properties_t *presenter_live_controls = obs_properties_create();
    obs_property_t *presenter_live_help =
      obs_properties_add_text(presenter_live_controls, "pptbridge_presenter_live_control_help", kPresenterLiveControlHelp, OBS_TEXT_INFO);
    obs_property_text_set_info_type(presenter_live_help, OBS_TEXT_INFO_WARNING);
    obs_property_text_set_info_word_wrap(presenter_live_help, true);
    obs_properties_add_button(
      presenter_live_controls,
      "pptbridge_start_live_btn",
      "Start / Restart PowerPoint Live Mode",
      control_start_live);
    obs_properties_add_button(
      presenter_live_controls,
      "pptbridge_stop_live_btn",
      "Stop PowerPoint Live Mode",
      control_stop_live);
    obs_properties_add_group(
      props,
      "pptbridge_presenter_live_controls_group",
      "PowerPoint Live Start / Stop",
      OBS_GROUP_NORMAL,
      presenter_live_controls);
  }
  if (context && context->mode == ViewMode::Slide) {
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

  if (context && context->mode == ViewMode::Slide) {
    obs_property_t *resize_help =
      obs_properties_add_text(props, "pptbridge_live_resize_help", kLiveResizeHelp, OBS_TEXT_INFO);
    obs_property_text_set_info_type(resize_help, OBS_TEXT_INFO_NORMAL);
    obs_property_text_set_info_word_wrap(resize_help, true);
  }

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
  const auto presenter_width_setting = static_cast<uint32_t>(std::max<int64_t>(0, obs_data_get_int(settings, "canvas_width")));
  const auto presenter_height_setting = static_cast<uint32_t>(std::max<int64_t>(0, obs_data_get_int(settings, "canvas_height")));
  const uint32_t width = (context->mode == ViewMode::Slide)
    ? 1920u
    : (presenter_width_setting >= 320u ? presenter_width_setting : 1920u);
  const uint32_t height = (context->mode == ViewMode::Slide)
    ? 1080u
    : (presenter_height_setting >= 240u ? presenter_height_setting : 1080u);
  const bool use_live_powerpoint =
    context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "use_live_powerpoint") : true;
  const bool auto_start_live_powerpoint =
    context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "auto_start_live_powerpoint") : false;
  const bool close_live_powerpoint_on_shutdown =
    context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "close_live_powerpoint_on_shutdown") : false;
  const LiveCaptureResizeMode live_capture_resize_mode =
    live_capture_resize_mode_from_setting(obs_data_get_string(settings, "live_capture_resize_mode"));
  const bool audio_enabled = context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "audio_enabled") : false;
  const bool use_live_app_audio =
    context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "use_live_app_audio") : false;
  const bool auto_recover_live =
    context->mode == ViewMode::Slide ? obs_data_get_bool(settings, "auto_recover_live") : false;
  const double audio_gain_db = context->mode == ViewMode::Slide ? obs_data_get_double(settings, "audio_gain_db") : 0.0;
  const PresenterRenderOptions presenter_options = presenter_options_from_settings(settings);
  const bool osc_feedback_enabled = obs_data_get_bool(settings, "pptbridge_osc_feedback_enabled");
  const char *osc_feedback_host = obs_data_get_string(settings, "pptbridge_osc_feedback_host");
  const uint16_t osc_feedback_port =
    static_cast<uint16_t>(std::clamp<int64_t>(obs_data_get_int(settings, "pptbridge_osc_feedback_port"), 1, 65535));

  const std::shared_ptr<PresentationDocument> old_document = context->document;
  const bool old_use_live_powerpoint = context->use_live_powerpoint;
  const bool old_close_live_powerpoint_on_shutdown = context->close_live_powerpoint_on_shutdown;
  const bool path_changed = context->pptx_path != (path ? path : "");
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
    (path_changed || (live_mode_changed && !use_live_powerpoint));

  if (should_stop_old_live) {
    clear_live_capture_source(context);
    clear_live_audio_source(context);
    old_document->StopLivePowerPoint();
  }

  context->pptx_path = path ? path : "";
  context->width = width;
  context->height = height;
  context->use_live_powerpoint = use_live_powerpoint;
  context->auto_start_live_powerpoint = auto_start_live_powerpoint;
  context->close_live_powerpoint_on_shutdown = close_live_powerpoint_on_shutdown;
  context->live_capture_resize_mode = live_capture_resize_mode;
  context->audio_enabled = audio_enabled;
  context->use_live_app_audio = use_live_app_audio;
  context->auto_recover_live = auto_recover_live;
  context->audio_gain_db = audio_gain_db;
  context->presenter_options = presenter_options;
  context->osc_feedback_enabled = osc_feedback_enabled;
  context->osc_feedback_host = (osc_feedback_host && *osc_feedback_host) ? osc_feedback_host : "127.0.0.1";
  context->osc_feedback_port = osc_feedback_port;

  if (!context->pptx_path.empty()) {
    Registry::Instance().AttachSource(
      context,
      context->pptx_path,
      context->mode == ViewMode::Slide ? RegisteredSourceKind::Slide : RegisteredSourceKind::Presenter);
  } else {
    Registry::Instance().DetachSource(context);
  }

  if (path_changed || live_mode_changed) {
    if (path_changed) {
      context->cue_export_status.clear();
    }
    context->osc_feedback_last_state_version = 0;
    context->osc_feedback_last_timer_second = 0;
    context->osc_feedback_status.clear();
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

  if (path_changed || size_changed || live_mode_changed || live_auto_start_changed || presenter_options_changed) {
    source_destroy_texture(context);
  }

  context->rendered_state_version = 0;
  context->rendered_timer_second = 0;
  context->last_live_sync_request = std::chrono::steady_clock::time_point::min();
}

void source_tick(SourceContext *context)
{
  if (context && context->document) {
    context->document->EnsureLoadingAsync();
    const bool source_visible = context->source && (obs_source_showing(context->source) || obs_source_active(context->source));
    if (source_visible) {
      Registry::Instance().SetActive(context->document);
    }

    const bool should_sync_live =
      context->document->IsLivePowerPointEnabled() &&
      ((context->mode == ViewMode::Slide && context->use_live_powerpoint) ||
       (context->mode == ViewMode::Presenter && source_visible));
    if (should_sync_live) {
      const auto now = std::chrono::steady_clock::now();
      const auto interval = source_visible ? kLiveSyncIntervalActive : kLiveSyncIntervalIdle;
      if (context->last_live_sync_request == std::chrono::steady_clock::time_point::min() ||
          now - context->last_live_sync_request >= interval) {
        context->last_live_sync_request = now;
        context->document->SyncLiveStateAsync();
      }
    }
    send_osc_status(context, false);
  }

  sync_live_capture_source(context);
  sync_live_audio_source(context);
  sync_media_sources(context);

  if (!context || context->mode != ViewMode::Slide || !context->document) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (context->live_capture_source) {
    update_live_capture_hook_state(context);
  }
  if (context->live_audio_source) {
    context->live_audio_hooked = query_hooked_source_state(context->live_audio_source).hooked;
  }

  if (context->live_capture_source && context->live_capture_hooked) {
    context->live_capture_last_seen = now;
  }
  if (context->live_audio_source && context->live_audio_hooked) {
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
    context->live_watchdog_ready = false;
    return;
  }

  if (!context->live_watchdog_ready) {
    context->live_watchdog_ready = true;
    context->live_capture_last_seen = now;
    context->live_audio_last_seen = now;
    context->live_recover_last_attempt = std::chrono::steady_clock::time_point::min();
    context->live_reload_last_attempt = std::chrono::steady_clock::time_point::min();
  }

  if ((!context->live_capture_source || !context->live_capture_hooked) &&
      now - context->live_capture_last_seen >= kLiveRecoverRetryDelay &&
      (context->live_recover_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_recover_last_attempt >= kLiveRecoverRetryDelay)) {
    blog(LOG_WARNING, "[PPTBridge SK] Windows live slideshow capture missing; attempting automatic reattach");
    context->live_recover_last_attempt = now;
    clear_live_capture_source(context);
    clear_live_audio_source(context);
    context->document->SyncLiveStateAsync();
  }

  if ((!context->live_capture_source || !context->live_capture_hooked) &&
      now - context->live_capture_last_seen >= kLiveReloadDelay &&
      (context->live_reload_last_attempt == std::chrono::steady_clock::time_point::min() ||
       now - context->live_reload_last_attempt >= kLiveReloadDelay)) {
    blog(
      LOG_WARNING,
      "[PPTBridge SK] Windows live slideshow capture did not recover yet; keeping PowerPoint running and using fallback render");
    context->live_reload_last_attempt = now;
    context->document->SyncLiveStateAsync();
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
  if (context->mode == ViewMode::Slide &&
      context->close_live_powerpoint_on_shutdown &&
      context->document &&
      Registry::Instance().CountSources(context->pptx_path, RegisteredSourceKind::Slide) == 0) {
    context->document->StopLivePowerPoint();
  }
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
  if (!context || context->mode != ViewMode::Slide || !context->audio_enabled) {
    return false;
  }

  const float gain = audio_gain_multiplier_db(context->audio_gain_db);
  uint64_t direct_wav_timestamp = 0;
  const bool mixed_direct_wav =
    mix_direct_wav_audio(context, audio_output, mixers, channels, sample_rate, gain, direct_wav_timestamp);
  auto playback = snapshot_audio_children(context);
  uint64_t timestamp = 0;
  if (mixed_direct_wav) {
    timestamp = direct_wav_timestamp;
  }
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

  if (context->live_capture_source && context->live_capture_active) {
    enum_callback(context->source, context->live_capture_source, param);
  }
  if (context->live_audio_source && context->live_audio_active) {
    enum_callback(context->source, context->live_audio_source, param);
  }

  std::lock_guard<std::mutex> lock(context->media_mutex);
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

  if (context->live_capture_source) {
    enum_callback(context->source, context->live_capture_source, param);
  }
  if (context->live_audio_source) {
    enum_callback(context->source, context->live_audio_source, param);
  }

  std::lock_guard<std::mutex> lock(context->media_mutex);
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

#endif  // _WIN32
