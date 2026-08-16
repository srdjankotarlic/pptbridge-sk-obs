#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace pptbridge {

struct SlideMetadata {
  std::string title;
  std::string notes;
};

enum class EmbeddedMediaKind {
  Video,
  Audio,
};

struct EmbeddedMedia {
  EmbeddedMediaKind kind = EmbeddedMediaKind::Video;
  std::string file_path;
  std::string original_entry;
  double x = 0.0;
  double y = 0.0;
  double width = 0.0;
  double height = 0.0;
  bool autoplay = true;
  bool loop = false;
};

enum class PresenterLayoutPreset {
  Balanced,
  LargePreview,
  LargeNotes,
  Compact,
  ConfidenceMonitor,
};

enum class PresenterPreviewScaleMode {
  Fit,
  Fill,
  Crop,
};

enum class PresenterBackgroundImageMode {
  Fill,
  Fit,
  Watermark,
};

struct PresenterRenderOptions {
  PresenterLayoutPreset layout = PresenterLayoutPreset::Balanced;
  PresenterPreviewScaleMode preview_scale_mode = PresenterPreviewScaleMode::Fit;
  PresenterBackgroundImageMode background_image_mode = PresenterBackgroundImageMode::Watermark;
  double preview_scale_percent = 100.0;
  double preview_position_x = 0.0;
  double preview_position_y = 0.0;
  double side_panel_width_percent = 100.0;
  double notes_font_size = 16.0;
  double notes_area_percent = 100.0;
  double notes_zoom_percent = 100.0;
  double notes_position_y = 0.0;
  uint32_t background_color = 0x0d121a;
  std::string background_image_path;
  double background_image_opacity_percent = 22.0;
  bool show_cue_list = false;
};

struct CueListItem {
  std::size_t index = 0;
  std::size_t number = 0;
  std::string title;
  bool current = false;
  bool next = false;
  bool checked = false;
};

struct PresentationStatus {
  std::string deck_name;
  std::string deck_path;
  std::string source_name;
  std::string error;
  std::size_t current_index = 0;
  std::size_t current_slide = 0;
  std::size_t total_slides = 0;
  std::string current_title;
  std::string next_title;
  uint64_t timer_seconds = 0;
  bool live_enabled = false;
  bool live_ready = false;
  bool loading = false;
  bool loaded = false;
  bool black_screen = false;
  bool current_cue_checked = false;
  bool next_cue_checked = false;
  std::size_t checked_count = 0;
  double slide_aspect_ratio = 16.0 / 9.0;
  double live_window_left = 0.0;
  double live_window_top = 0.0;
  double live_window_width = 0.0;
  double live_window_height = 0.0;
  std::vector<CueListItem> cues;
};

class PresentationDocument : public std::enable_shared_from_this<PresentationDocument> {
public:
  explicit PresentationDocument(std::string pptx_path);
  ~PresentationDocument();

  const std::string &Path() const;
  std::string Name() const;

  void SetLivePowerPointEnabled(bool enabled);
  void SetLivePowerPointAutoStart(bool enabled);
  bool IsLivePowerPointEnabled() const;
  bool IsLivePowerPointReady() const;
  std::string LiveWindowTitle() const;
  void StartLivePowerPointAsync();
  void StopLivePowerPoint();
  void StopLivePowerPointAsync();
  void SyncLiveStateAsync();
  void SetPresenterAssetsWanted(bool wanted);

  void EnsureLoadingAsync();
  void ReloadAsync();

  bool IsLoaded() const;
  bool IsLoading() const;
  std::string LastError() const;

  std::size_t SlideCount() const;
  std::size_t CurrentIndex() const;
  bool HasNext() const;
  bool HasPrevious() const;
  bool IsBlackScreen() const;

  void Next();
  void Previous();
  void First();
  void Last();
  void GoTo(std::size_t index);
  void ToggleBlackScreen();

  uint64_t StateVersion() const;
  uint64_t PresentationSeconds() const;
  std::vector<EmbeddedMedia> CurrentMedia() const;
  PresentationStatus SnapshotStatus() const;
  bool SetCueChecked(std::size_t index, bool checked);
  bool ToggleCueChecked(std::size_t index);
  void ClearCueChecks();
  bool ExportCueList(std::string &out_path, std::string &out_error) const;

  bool RenderSlideBGRA(
    uint32_t width,
    uint32_t height,
    std::vector<uint8_t> &out_pixels,
    uint32_t &out_stride
  ) const;

  bool RenderPresenterBGRA(
    uint32_t width,
    uint32_t height,
    std::vector<uint8_t> &out_pixels,
    uint32_t &out_stride,
    const PresenterRenderOptions &options
  ) const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;

  void StartLoadIfNeeded(bool force_reload);
  void LoadOnWorker();
  void StopLivePowerPointOnLiveQueue(
    uint64_t request_generation,
    std::string cache_dir,
    std::string presentation_path,
    std::string window_title);
  void RunLivePowerPointCommandAsync(
    std::string command_line,
    bool clear_black);
};

}  // namespace pptbridge
