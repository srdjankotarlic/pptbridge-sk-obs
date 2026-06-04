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

    const auto start = std::chrono::steady_clock::now();
    while (!document->IsLoaded()) {
      const auto error = document->LastError();
      if (!error.empty()) {
        std::fprintf(stderr, "load failed: %s\n", error.c_str());
        return 1;
      }
      if (std::chrono::steady_clock::now() - start > std::chrono::seconds(30)) {
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
    if (!document->RenderPresenterBGRA(1280, 720, pixels, stride, options) || pixels.empty()) {
      std::fprintf(stderr, "presenter render failed\n");
      return 1;
    }
    std::printf("presenter render: %zu bytes stride=%u\n", pixels.size(), stride);

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
