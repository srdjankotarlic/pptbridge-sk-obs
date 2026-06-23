#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <vector>

using pptbridge::PresentationDocument;
using pptbridge::PresenterRenderOptions;

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

    std::printf("loaded: %zu slides\n", document->SlideCount());

    std::vector<uint8_t> pixels;
    uint32_t stride = 0;
    if (!document->RenderSlideBGRA(1920, 1080, pixels, stride) || pixels.empty()) {
      std::fprintf(stderr, "slide render failed\n");
      return 1;
    }
    std::printf("slide render: %zu bytes stride=%u\n", pixels.size(), stride);

    PresenterRenderOptions options;
    options.show_cue_list = true;
    if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) || pixels.empty()) {
      std::fprintf(stderr, "presenter render failed\n");
      return 1;
    }
    std::printf("presenter render: %zu bytes stride=%u\n", pixels.size(), stride);

    if (document->SlideCount() > 0) {
      const auto initial_status = document->SnapshotStatus();
      if (initial_status.cues.empty()) {
        std::fprintf(stderr, "cue status missing cues\n");
        return 1;
      }

      if (!document->SetCueChecked(initial_status.current_index, true)) {
        std::fprintf(stderr, "set current cue checked failed\n");
        return 1;
      }
      auto cue_status = document->SnapshotStatus();
      if (!cue_status.current_cue_checked || cue_status.checked_count != 1) {
        std::fprintf(stderr, "current cue checked state wrong\n");
        return 1;
      }

      if (document->SlideCount() > 1) {
        if (!document->SetCueChecked(initial_status.current_index + 1, true)) {
          std::fprintf(stderr, "set next cue checked failed\n");
          return 1;
        }
        cue_status = document->SnapshotStatus();
        if (!cue_status.next_cue_checked || cue_status.checked_count != 2) {
          std::fprintf(stderr, "next cue checked state wrong\n");
          return 1;
        }
      }

      document->ClearCueChecks();
      cue_status = document->SnapshotStatus();
      if (cue_status.checked_count != 0 || cue_status.current_cue_checked || cue_status.next_cue_checked) {
        std::fprintf(stderr, "clear cue checks failed\n");
        return 1;
      }
      std::printf("cue status ok: cues=%zu\n", cue_status.cues.size());
    }

    document->Next();
    document->Next();
    document->Previous();
    document->Last();
    document->Next();
    document->First();

    if (!document->RenderSlideBGRA(1920, 1080, pixels, stride) || pixels.empty()) {
      std::fprintf(stderr, "post-nav slide render failed\n");
      return 1;
    }
    if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) || pixels.empty()) {
      std::fprintf(stderr, "post-nav presenter render failed\n");
      return 1;
    }
    std::printf("navigation render ok: current=%zu\n", document->CurrentIndex() + 1);
  }

  return 0;
}
