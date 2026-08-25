#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

using pptbridge::PresentationDocument;
using pptbridge::PresenterRenderOptions;

namespace fs = std::filesystem;

namespace {

int LoadTimeoutSeconds()
{
  const char *raw_timeout = std::getenv("PPTBRIDGE_RENDER_SMOKE_TIMEOUT_SECONDS");
  if (!raw_timeout || raw_timeout[0] == '\0') {
    return 30;
  }
  const int parsed = std::atoi(raw_timeout);
  return parsed > 0 ? parsed : 30;
}

uint64_t PixelHash(const std::vector<uint8_t> &pixels)
{
  uint64_t hash = 1469598103934665603ULL;
  for (const auto byte : pixels) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  return hash;
}

bool IsSolidBlackRgb(
  const std::vector<uint8_t> &pixels,
  uint32_t stride,
  uint32_t width,
  uint32_t height)
{
  if (stride < width * 4 || pixels.size() < static_cast<std::size_t>(stride) * height) {
    return false;
  }
  for (uint32_t y = 0; y < height; ++y) {
    const auto *row = pixels.data() + static_cast<std::size_t>(stride) * y;
    for (uint32_t x = 0; x < width; ++x) {
      const auto *pixel = row + static_cast<std::size_t>(x) * 4;
      if (pixel[0] != 0 || pixel[1] != 0 || pixel[2] != 0) {
        return false;
      }
    }
  }
  return true;
}

} // namespace

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc < 2) {
      std::fprintf(stderr, "usage: %s /path/to/deck.pptx-or.pdf\n", argv[0]);
      return 2;
    }

    auto document = std::make_shared<PresentationDocument>(std::string(argv[1]));
    document->SetPresenterAssetsWanted(true);
    document->EnsureLoadingAsync();

    const auto load_timeout = std::chrono::seconds(LoadTimeoutSeconds());
    const auto start = std::chrono::steady_clock::now();
    while (!document->IsLoaded()) {
      const auto error = document->LastError();
      if (!error.empty()) {
        std::fprintf(stderr, "load failed: %s\n", error.c_str());
        return 1;
      }
      if (std::chrono::steady_clock::now() - start > load_timeout) {
        std::fprintf(stderr, "load timed out\n");
        return 1;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const auto first_preview_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - start).count();
    while (document->IsLoading()) {
      const auto error = document->LastError();
      if (!error.empty()) {
        std::fprintf(stderr, "metadata load failed: %s\n", error.c_str());
        return 1;
      }
      if (std::chrono::steady_clock::now() - start > load_timeout) {
        std::fprintf(stderr, "metadata load timed out\n");
        return 1;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const auto slide_count = document->SlideCount();
    if (slide_count == 0) {
      std::fprintf(stderr, "loaded deck has no slides\n");
      return 1;
    }
    std::printf("loaded: %zu slides, first preview=%lld ms\n", slide_count, first_preview_ms);

    std::vector<uint8_t> pixels;
    uint32_t stride = 0;
    if (!document->RenderSlideBGRA(1920, 1080, pixels, stride) || pixels.empty()) {
      std::fprintf(stderr, "slide render failed\n");
      return 1;
    }
    std::printf("slide render: %zu bytes stride=%u\n", pixels.size(), stride);

    const std::vector<pptbridge::PresenterLayoutPreset> layouts = {
      pptbridge::PresenterLayoutPreset::Balanced,
      pptbridge::PresenterLayoutPreset::LargePreview,
      pptbridge::PresenterLayoutPreset::LargeNotes,
      pptbridge::PresenterLayoutPreset::Compact,
      pptbridge::PresenterLayoutPreset::ConfidenceMonitor,
    };
    const std::vector<pptbridge::PresenterPreviewScaleMode> scale_modes = {
      pptbridge::PresenterPreviewScaleMode::Fit,
      pptbridge::PresenterPreviewScaleMode::Fill,
      pptbridge::PresenterPreviewScaleMode::Crop,
    };
    PresenterRenderOptions options;
    options.show_cue_list = true;
    uint64_t default_presenter_hash = 0;
    for (const auto layout : layouts) {
      options.layout = layout;
      for (const auto scale_mode : scale_modes) {
        options.preview_scale_mode = scale_mode;
        if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) ||
            pixels.size() < static_cast<std::size_t>(stride) * 720 ||
            stride < 1280 * 4) {
          std::fprintf(stderr, "presenter layout/scale render failed\n");
          return 1;
        }
        if (layout == pptbridge::PresenterLayoutPreset::Balanced &&
            scale_mode == pptbridge::PresenterPreviewScaleMode::Fit) {
          default_presenter_hash = PixelHash(pixels);
        }
      }
    }
    std::printf("presenter render matrix: %zu bytes stride=%u\n", pixels.size(), stride);

    options.layout = pptbridge::PresenterLayoutPreset::LargeNotes;
    options.preview_scale_mode = pptbridge::PresenterPreviewScaleMode::Crop;
    options.preview_scale_percent = 140.0;
    options.preview_position_x = 18.0;
    options.preview_position_y = -12.0;
    options.side_panel_width_percent = 125.0;
    options.notes_font_size = 24.0;
    options.notes_area_percent = 120.0;
    options.notes_zoom_percent = 135.0;
    options.notes_position_y = 14.0;
    options.background_color = 0x315a44;
    options.background_image_opacity_percent = 55.0;
    if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) ||
        PixelHash(pixels) == default_presenter_hash) {
      std::fprintf(stderr, "custom presenter controls did not change the output\n");
      return 1;
    }

    const char *background_image = std::getenv("PPTBRIDGE_TEST_BACKGROUND_IMAGE");
    if (background_image && background_image[0] != '\0') {
      options.background_image_path = background_image;
      std::vector<uint64_t> image_mode_hashes;
      for (const auto image_mode : {
             pptbridge::PresenterBackgroundImageMode::Fill,
             pptbridge::PresenterBackgroundImageMode::Fit,
             pptbridge::PresenterBackgroundImageMode::Watermark,
           }) {
        options.background_image_mode = image_mode;
        if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options)) {
          std::fprintf(stderr, "presenter background image render failed\n");
          return 1;
        }
        image_mode_hashes.push_back(PixelHash(pixels));
      }
      if (image_mode_hashes[0] == image_mode_hashes[1] &&
          image_mode_hashes[1] == image_mode_hashes[2]) {
        std::fprintf(stderr, "presenter background image modes produced identical output\n");
        return 1;
      }
      std::printf("presenter background image modes ok\n");
    }

    if (document->RenderSlideBGRA(0, 720, pixels, stride) ||
        document->RenderPresenterBGRA(1280, 0, pixels, stride, options)) {
      std::fprintf(stderr, "zero-sized render unexpectedly succeeded\n");
      return 1;
    }

    const auto initial_status = document->SnapshotStatus();
    if (!initial_status.loaded || initial_status.loading || !initial_status.error.empty() ||
        initial_status.total_slides != slide_count || initial_status.current_slide != 1 ||
        initial_status.current_index != 0 || initial_status.cues.size() != slide_count) {
      std::fprintf(stderr, "initial presentation status is inconsistent\n");
      return 1;
    }
    if (document->HasPrevious()) {
      std::fprintf(stderr, "first slide unexpectedly has a previous slide\n");
      return 1;
    }

    std::size_t media_count = 0;
    for (std::size_t index = 0; index < slide_count; ++index) {
      document->GoTo(index);
      // In cached mode the first Next cue starts embedded media and a later
      // Next advances the slide, matching how the OBS source behaves live.
      document->Next();
      for (const auto &media : document->CurrentMedia()) {
        if (media.file_path.empty() || !fs::is_regular_file(media.file_path) ||
            media.x < 0.0 || media.y < 0.0 || media.width <= 0.0 || media.height <= 0.0) {
          std::fprintf(stderr, "embedded media metadata is invalid on slide %zu\n", index + 1);
          return 1;
        }
        ++media_count;
      }
    }
    document->First();
    const char *expected_media_raw = std::getenv("PPTBRIDGE_TEST_EXPECT_MEDIA_COUNT");
    if (expected_media_raw && expected_media_raw[0] != '\0' &&
        media_count != static_cast<std::size_t>(std::strtoull(expected_media_raw, nullptr, 10))) {
      std::fprintf(stderr, "embedded media count mismatch: got %zu expected %s\n", media_count, expected_media_raw);
      return 1;
    }
    std::printf("embedded media metadata ok: %zu item(s)\n", media_count);

    const auto cue_version = document->StateVersion();
    if (!document->SetCueChecked(initial_status.current_index, true)) {
      std::fprintf(stderr, "set current cue checked failed\n");
      return 1;
    }
    auto cue_status = document->SnapshotStatus();
    if (!cue_status.current_cue_checked || cue_status.checked_count != 1 ||
        document->StateVersion() <= cue_version) {
      std::fprintf(stderr, "current cue checked state wrong\n");
      return 1;
    }

    if (slide_count > 1) {
      if (!document->ToggleCueChecked(initial_status.current_index + 1)) {
        std::fprintf(stderr, "toggle next cue checked failed\n");
        return 1;
      }
      cue_status = document->SnapshotStatus();
      if (!cue_status.next_cue_checked || cue_status.checked_count != 2) {
        std::fprintf(stderr, "next cue checked state wrong\n");
        return 1;
      }
    }
    if (document->SetCueChecked(slide_count, true) || document->ToggleCueChecked(slide_count)) {
      std::fprintf(stderr, "out-of-range cue unexpectedly succeeded\n");
      return 1;
    }
    document->ClearCueChecks();
    cue_status = document->SnapshotStatus();
    if (cue_status.checked_count != 0 || cue_status.current_cue_checked || cue_status.next_cue_checked) {
      std::fprintf(stderr, "clear cue checks failed\n");
      return 1;
    }
    std::printf("cue status ok: cues=%zu\n", cue_status.cues.size());

    if (std::getenv("PPTBRIDGE_TEST_EXPORT_CUES")) {
      if (!document->SetCueChecked(0, true)) {
        std::fprintf(stderr, "could not prepare cue export state\n");
        return 1;
      }
      std::string cue_path;
      std::string cue_error;
      if (!document->ExportCueList(cue_path, cue_error)) {
        std::fprintf(stderr, "cue export failed: %s\n", cue_error.c_str());
        return 1;
      }
      std::ifstream cue_file(cue_path);
      std::ostringstream cue_text;
      cue_text << cue_file.rdbuf();
      const auto exported = cue_text.str();
      if (!cue_file || exported.find("PPTBridge SK Cue List") == std::string::npos ||
          exported.find("[x] > 1.") == std::string::npos) {
        std::fprintf(stderr, "cue export content is incomplete: %s\n", cue_path.c_str());
        return 1;
      }
      std::error_code remove_error;
      fs::remove(cue_path, remove_error);
      if (remove_error) {
        std::fprintf(stderr, "could not clean cue export: %s\n", remove_error.message().c_str());
        return 1;
      }
      document->ClearCueChecks();
      std::printf("cue export ok\n");
    }

    const auto black_version = document->StateVersion();
    document->ToggleBlackScreen();
    if (!document->IsBlackScreen() || !document->SnapshotStatus().black_screen ||
        document->StateVersion() <= black_version) {
      std::fprintf(stderr, "black-screen enable failed\n");
      return 1;
    }
    if (!document->RenderSlideBGRA(640, 360, pixels, stride) ||
        !IsSolidBlackRgb(pixels, stride, 640, 360)) {
      std::fprintf(stderr, "black-screen render is not solid black\n");
      return 1;
    }
    document->ToggleBlackScreen();
    if (document->IsBlackScreen()) {
      std::fprintf(stderr, "black-screen disable failed\n");
      return 1;
    }

    document->Last();
    if (document->CurrentIndex() != slide_count - 1 || document->HasNext()) {
      std::fprintf(stderr, "last-slide navigation state wrong\n");
      return 1;
    }
    document->Next();
    if (document->CurrentIndex() != slide_count - 1) {
      std::fprintf(stderr, "next advanced beyond final slide\n");
      return 1;
    }
    if (slide_count > 1) {
      const bool final_media_triggered = !document->CurrentMedia().empty();
      document->Previous();
      if (final_media_triggered) {
        if (document->CurrentIndex() != slide_count - 1 || !document->CurrentMedia().empty()) {
          std::fprintf(stderr, "previous did not stop final-slide media first\n");
          return 1;
        }
        document->Previous();
      }
      if (document->CurrentIndex() != slide_count - 2 || !document->HasNext()) {
        std::fprintf(stderr, "previous navigation failed\n");
        return 1;
      }
      document->GoTo(1);
      if (document->CurrentIndex() != 1 || !document->HasPrevious()) {
        std::fprintf(stderr, "go-to navigation failed\n");
        return 1;
      }
      document->GoTo(slide_count);
      if (document->CurrentIndex() != 1) {
        std::fprintf(stderr, "out-of-range go-to changed the slide\n");
        return 1;
      }
    }
    document->First();
    if (document->CurrentIndex() != 0 || document->HasPrevious()) {
      std::fprintf(stderr, "first-slide navigation state wrong\n");
      return 1;
    }

    if (!document->RenderSlideBGRA(1920, 1080, pixels, stride) || pixels.empty()) {
      std::fprintf(stderr, "post-nav slide render failed\n");
      return 1;
    }
    if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) || pixels.empty()) {
      std::fprintf(stderr, "post-nav presenter render failed\n");
      return 1;
    }
    std::printf("navigation/state render ok: current=%zu\n", document->CurrentIndex() + 1);
  }

  return 0;
}
