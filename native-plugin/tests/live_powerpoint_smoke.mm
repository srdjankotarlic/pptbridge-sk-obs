#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>

using pptbridge::PresentationDocument;

namespace {

bool WaitForLiveReady(
  const std::shared_ptr<PresentationDocument> &document,
  std::chrono::seconds timeout,
  const char *label)
{
  const auto started = std::chrono::steady_clock::now();
  while (!document->IsLivePowerPointReady()) {
    const auto error = document->LastError();
    if (!error.empty() && std::chrono::steady_clock::now() - started > std::chrono::seconds(2)) {
      std::fprintf(stderr, "%s failed: %s\n", label, error.c_str());
      return false;
    }
    if (std::chrono::steady_clock::now() - started > timeout) {
      std::fprintf(stderr, "%s timed out\n", label);
      return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return true;
}

} // namespace

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

    // A stop issued while PowerPoint is still starting must win. The
    // synchronous cleanup waits for the serial live queue to drain, making
    // this a deterministic regression check for stale start completions.
    document->StartLivePowerPointAsync();
    document->StopLivePowerPointAsync();
    document->StopLivePowerPoint();
    if (document->IsLivePowerPointReady() || !document->LastError().empty()) {
      std::fprintf(
        stderr,
        "rapid start/stop left a live session or error: %s\n",
        document->LastError().c_str());
      return 1;
    }
    std::printf("rapid start/stop ordering ok\n");

    document->StartLivePowerPointAsync();
    if (!WaitForLiveReady(document, std::chrono::seconds(60), "live start")) {
      document->StopLivePowerPoint();
      return 1;
    }

    std::printf(
      "live start ok: title=%s slides=%zu\n",
      document->LiveWindowTitle().c_str(),
      document->SlideCount());

    // A newer start issued immediately after stop must survive the older stop
    // completion and create a fresh, controllable live session.
    document->StopLivePowerPointAsync();
    document->StartLivePowerPointAsync();
    if (!WaitForLiveReady(document, std::chrono::seconds(60), "rapid stop/start")) {
      document->StopLivePowerPoint();
      return 1;
    }

    std::printf("rapid stop/start ordering ok\n");
    document->StopLivePowerPoint();
    if (document->IsLivePowerPointReady()) {
      std::fprintf(stderr, "restarted live session still ready after final stop\n");
      return 1;
    }
  }

  return 0;
}
