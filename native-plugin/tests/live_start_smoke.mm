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

bool wait_for_command_settled(
  const std::shared_ptr<PresentationDocument> &document,
  uint64_t version_before_command,
  const char *label,
  std::chrono::seconds timeout = std::chrono::seconds(20))
{
  const auto start = std::chrono::steady_clock::now();
  while (std::chrono::steady_clock::now() - start < timeout) {
    const auto error = document->LastError();
    if (!error.empty() || !document->IsLivePowerPointReady()) {
      std::fprintf(stderr, "%s failed: %s\n", label, error.c_str());
      return false;
    }
    if (document->StateVersion() > version_before_command) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  std::fprintf(
    stderr,
    "%s timed out: current slide %zu, version=%llu\n",
    label,
    document->CurrentIndex() + 1,
    static_cast<unsigned long long>(document->StateVersion()));
  return false;
}

bool wait_for_command_at_index(
  const std::shared_ptr<PresentationDocument> &document,
  uint64_t version_before_command,
  std::size_t expected,
  const char *label)
{
  if (!wait_for_command_settled(document, version_before_command, label)) {
    return false;
  }
  if (document->CurrentIndex() == expected) {
    return true;
  }
  std::fprintf(
    stderr,
    "%s returned slide %zu instead of slide %zu\n",
    label,
    document->CurrentIndex() + 1,
    expected + 1);
  return false;
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

    const auto slide_count = document->SlideCount();
    if (slide_count == 0 || document->LiveWindowTitle().empty()) {
      std::fprintf(stderr, "live session has no slides or window title\n");
      document->StopLivePowerPoint();
      return 1;
    }

    const auto assets_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(90);
    while (document->IsLoading() && std::chrono::steady_clock::now() < assets_deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (document->IsLoading()) {
      std::fprintf(stderr, "static presenter assets did not finish loading\n");
      document->StopLivePowerPoint();
      return 1;
    }

    auto command_version = document->StateVersion();
    document->First();
    if (!wait_for_command_at_index(document, command_version, 0, "first slide")) {
      document->StopLivePowerPoint();
      return 1;
    }

    if (slide_count > 1) {
      bool advanced_to_second_slide = false;
      for (int build_step = 0; build_step < 64; ++build_step) {
        command_version = document->StateVersion();
        document->Next();
        if (!wait_for_command_settled(document, command_version, "next slide/build")) {
          document->StopLivePowerPoint();
          return 1;
        }
        if (document->CurrentIndex() == 1) {
          advanced_to_second_slide = true;
          break;
        }
        if (document->CurrentIndex() != 0) {
          break;
        }
      }
      if (!advanced_to_second_slide) {
        std::fprintf(stderr, "next command did not reach slide 2 after animation builds\n");
        document->StopLivePowerPoint();
        return 1;
      }

      command_version = document->StateVersion();
      document->Last();
      if (!wait_for_command_at_index(document, command_version, slide_count - 1, "last slide")) {
        document->StopLivePowerPoint();
        return 1;
      }

      command_version = document->StateVersion();
      document->Next();
      if (!wait_for_command_at_index(document, command_version, slide_count - 1, "final-slide guard")) {
        std::fprintf(
          stderr,
          "final-slide guard failed: expected=%zu current=%zu ready=%s error='%s'\n",
          slide_count,
          document->CurrentIndex() + 1,
          document->IsLivePowerPointReady() ? "yes" : "no",
          document->LastError().c_str());
        document->StopLivePowerPoint();
        return 1;
      }

      bool returned_to_previous_slide = false;
      for (int build_step = 0; build_step < 64; ++build_step) {
        command_version = document->StateVersion();
        document->Previous();
        if (!wait_for_command_settled(document, command_version, "previous slide/build")) {
          document->StopLivePowerPoint();
          return 1;
        }
        if (document->CurrentIndex() == slide_count - 2) {
          returned_to_previous_slide = true;
          break;
        }
        if (document->CurrentIndex() != slide_count - 1) {
          break;
        }
      }
      if (!returned_to_previous_slide) {
        std::fprintf(stderr, "previous command did not reach the prior slide after animation builds\n");
        document->StopLivePowerPoint();
        return 1;
      }

      // A delayed navigation completion must not clear a newer Black command.
      command_version = document->StateVersion();
      document->Last();
      document->ToggleBlackScreen();
      if (!document->IsBlackScreen() ||
          !wait_for_command_at_index(document, command_version + 1, slide_count - 1, "navigation/black race")) {
        std::fprintf(stderr, "live navigation/black race setup failed\n");
        document->StopLivePowerPoint();
        return 1;
      }
      if (!document->IsBlackScreen()) {
        std::fprintf(stderr, "live navigation completion cleared a newer black-screen command\n");
        document->StopLivePowerPoint();
        return 1;
      }
      document->ToggleBlackScreen();
    }

    document->ToggleBlackScreen();
    if (!document->IsBlackScreen()) {
      std::fprintf(stderr, "live black-screen state did not enable\n");
      document->StopLivePowerPoint();
      return 1;
    }
    document->ToggleBlackScreen();
    if (document->IsBlackScreen()) {
      std::fprintf(stderr, "live black-screen state did not disable\n");
      document->StopLivePowerPoint();
      return 1;
    }

    std::printf(
      "live ready: %zu slides, window='%s', current=%zu\n",
      slide_count,
      document->LiveWindowTitle().c_str(),
      document->CurrentIndex() + 1);
    std::printf("live first/next/last/final-guard/previous/black checks passed\n");

    document->StopLivePowerPoint();
    if (document->IsLivePowerPointReady()) {
      std::fprintf(stderr, "live session still ready after synchronous stop\n");
      return 1;
    }
    const auto stop_error = document->LastError();
    if (!stop_error.empty()) {
      std::fprintf(stderr, "live session reported a stop error: %s\n", stop_error.c_str());
      return 1;
    }
    std::printf("live stop ok\n");
  }

  return 0;
}
