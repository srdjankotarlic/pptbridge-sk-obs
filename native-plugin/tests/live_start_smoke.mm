#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>

using pptbridge::PresentationDocument;

namespace {

bool wait_for_live_ready(const std::shared_ptr<PresentationDocument> &document)
{
  const auto start = std::chrono::steady_clock::now();
  while (!document->IsLivePowerPointReady()) {
    const auto error = document->LastError();
    if (error.find("PowerPoint live mode failed") != std::string::npos ||
        error.find("PowerPoint slideshow is not available") != std::string::npos) {
      std::fprintf(stderr, "live start failed: %s\n", error.c_str());
      return false;
    }
    if (std::chrono::steady_clock::now() - start > std::chrono::seconds(90)) {
      std::fprintf(stderr, "live start timed out: %s\n", error.c_str());
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
    document->SetPresenterAssetsWanted(true);
    document->StartLivePowerPointAsync();
    if (!wait_for_live_ready(document)) {
      document->StopLivePowerPointAsync();
      return 1;
    }

    const auto initial_index = document->CurrentIndex();
    document->Next();
    std::this_thread::sleep_for(std::chrono::seconds(1));
    document->SyncLiveStateAsync();
    std::this_thread::sleep_for(std::chrono::seconds(1));

    std::printf(
      "live ready: %zu slides, window='%s', current=%zu\n",
      document->SlideCount(),
      document->LiveWindowTitle().c_str(),
      document->CurrentIndex() + 1);
    std::printf("navigation attempted from slide %zu\n", initial_index + 1);

    document->StopLivePowerPointAsync();
    std::this_thread::sleep_for(std::chrono::seconds(2));
  }

  return 0;
}
