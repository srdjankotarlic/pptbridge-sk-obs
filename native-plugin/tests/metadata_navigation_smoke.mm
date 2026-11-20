#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <memory>
#include <thread>

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc != 2) {
      std::fprintf(stderr, "usage: metadata_navigation_smoke /path/to/multi-slide.pptx\n");
      return 2;
    }

    using Clock = std::chrono::steady_clock;
    auto document = std::make_shared<pptbridge::PresentationDocument>(argv[1]);
    const auto deadline = Clock::now() + std::chrono::seconds(60);
    document->EnsureLoadingAsync();
    while (!document->IsLoaded() && document->IsLoading() && Clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (!document->IsLoaded() || !document->IsLoading() || document->SlideCount() < 2) {
      std::fprintf(stderr, "Expected the static preview before PPTX notes finished: %s\n",
                   document->LastError().c_str());
      return 2;
    }

    document->Next();
    document->ToggleBlackScreen();
    while (document->IsLoading() && Clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    const auto status = document->SnapshotStatus();
    if (status.loading || status.current_slide != 2 || !status.black_screen) {
      std::fprintf(stderr, "Notes load changed the on-air state: slide=%u blackout=%d loading=%d\n",
                   static_cast<unsigned>(status.current_slide), status.black_screen, status.loading);
      return 1;
    }
    std::puts("Slide 2 and blackout survived PPTX notes preparation.");
    return 0;
  }
}
