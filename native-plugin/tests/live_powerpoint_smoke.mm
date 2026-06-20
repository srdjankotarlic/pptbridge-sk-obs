#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>

using pptbridge::PresentationDocument;

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc < 2) {
      std::fprintf(stderr, "usage: %s /path/to/deck.pptx\n", argv[0]);
      return 2;
    }

    auto document = std::make_shared<PresentationDocument>(std::string(argv[1]));
    document->SetLivePowerPointEnabled(true);
    document->SetLivePowerPointAutoStart(false);
    document->EnsureLoadingAsync();

    const auto preview_start = std::chrono::steady_clock::now();
    while (!document->IsLoaded()) {
      const auto error = document->LastError();
      if (!error.empty()) {
        std::fprintf(stderr, "manual preview failed: %s\n", error.c_str());
        return 1;
      }
      if (std::chrono::steady_clock::now() - preview_start > std::chrono::seconds(45)) {
        std::fprintf(stderr, "manual preview timed out\n");
        return 1;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    std::printf(
      "manual live preview loaded: slides=%zu live_ready=%s\n",
      document->SlideCount(),
      document->IsLivePowerPointReady() ? "yes" : "no");

    document->StartLivePowerPointAsync();
    const auto live_start = std::chrono::steady_clock::now();
    while (!document->IsLivePowerPointReady()) {
      const auto error = document->LastError();
      if (!error.empty() && std::chrono::steady_clock::now() - live_start > std::chrono::seconds(2)) {
        std::fprintf(stderr, "live start failed: %s\n", error.c_str());
        return 1;
      }
      if (std::chrono::steady_clock::now() - live_start > std::chrono::seconds(60)) {
        std::fprintf(stderr, "live start timed out\n");
        return 1;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    std::printf(
      "live start ok: title=%s slides=%zu\n",
      document->LiveWindowTitle().c_str(),
      document->SlideCount());

    document->StopLivePowerPoint();
    std::printf("live stop ok: live_ready=%s\n", document->IsLivePowerPointReady() ? "yes" : "no");
  }

  return 0;
}
