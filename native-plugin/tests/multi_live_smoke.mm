#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <thread>

using pptbridge::PresentationDocument;

namespace {

bool WaitFor(
  const std::function<bool()> &predicate,
  std::chrono::seconds timeout,
  const char *description)
{
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    if (predicate()) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  std::fprintf(stderr, "timed out waiting for %s\n", description);
  return false;
}

bool StartLive(const std::shared_ptr<PresentationDocument> &document, const char *label)
{
  document->SetLivePowerPointEnabled(true);
  document->SetLivePowerPointAutoStart(false);
  document->StartLivePowerPointAsync();
  if (!WaitFor(
        [document]() { return document->IsLivePowerPointReady(); },
        std::chrono::seconds(60),
        label)) {
    const auto error = document->LastError();
    if (!error.empty()) {
      std::fprintf(stderr, "%s failed: %s\n", label, error.c_str());
    }
    return false;
  }
  return true;
}

bool WaitForCommand(
  const std::shared_ptr<PresentationDocument> &document,
  uint64_t version_before_command,
  const char *label)
{
  return WaitFor(
    [document, version_before_command]() {
      return document->StateVersion() > version_before_command &&
        document->IsLivePowerPointReady() && document->LastError().empty();
    },
    std::chrono::seconds(20),
    label);
}

bool AdvanceToSecondSlide(
  const std::shared_ptr<PresentationDocument> &document,
  const char *label)
{
  for (int build_step = 0; build_step < 64; ++build_step) {
    const auto version = document->StateVersion();
    document->Next();
    if (!WaitForCommand(document, version, label)) {
      return false;
    }
    if (document->CurrentIndex() == 1) {
      return true;
    }
    if (document->CurrentIndex() != 0) {
      return false;
    }
  }
  return false;
}

} // namespace

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc < 3) {
      std::fprintf(stderr, "usage: %s /path/to/deck-a.pptx /path/to/deck-b.pptx\n", argv[0]);
      return 2;
    }

    auto first = std::make_shared<PresentationDocument>(std::string(argv[1]));
    auto second = std::make_shared<PresentationDocument>(std::string(argv[2]));
    bool ok = StartLive(first, "first live deck") && StartLive(second, "second live deck");

    if (ok) {
      ok = WaitFor(
        [first, second]() { return !first->IsLoading() && !second->IsLoading(); },
        std::chrono::seconds(90),
        "both decks to finish presenter asset loading");
    }

    if (ok && (first->LiveWindowTitle().empty() || second->LiveWindowTitle().empty() ||
               first->LiveWindowTitle() == second->LiveWindowTitle())) {
      std::fprintf(stderr, "live deck window identities are not distinct\n");
      ok = false;
    }

    if (ok) {
      const auto first_version = first->StateVersion();
      const auto second_version = second->StateVersion();
      first->First();
      second->First();
      ok = WaitForCommand(first, first_version, "first deck to confirm slide one") &&
        WaitForCommand(second, second_version, "second deck to confirm slide one") &&
        first->CurrentIndex() == 0 && second->CurrentIndex() == 0;
    }

    if (ok) {
      ok = AdvanceToSecondSlide(first, "first deck to advance through builds");
      if (ok && second->CurrentIndex() != 0) {
        std::fprintf(stderr, "advancing the first deck changed the second deck\n");
        ok = false;
      }
    }

    if (ok) {
      const auto version = second->StateVersion();
      second->Last();
      ok = WaitForCommand(second, version, "second deck to reach its final slide") &&
        second->SlideCount() > 0 && second->CurrentIndex() + 1 == second->SlideCount();
      if (ok && first->CurrentIndex() != 1) {
        std::fprintf(stderr, "moving the second deck changed the first deck\n");
        ok = false;
      }
    }

    if (ok) {
      first->StopLivePowerPoint();
      if (!first->LastError().empty()) {
        std::fprintf(stderr, "stopping the first deck failed: %s\n", first->LastError().c_str());
        ok = false;
      } else if (first->IsLivePowerPointReady() || !second->IsLivePowerPointReady()) {
        std::fprintf(stderr, "stopping the first deck also stopped or corrupted the second deck\n");
        ok = false;
      }
    }

    first->StopLivePowerPoint();
    second->StopLivePowerPoint();
    if (first->IsLivePowerPointReady() || second->IsLivePowerPointReady()) {
      std::fprintf(stderr, "a live deck remained ready after final cleanup\n");
      ok = false;
    }
    if (!first->LastError().empty() || !second->LastError().empty()) {
      std::fprintf(
        stderr,
        "multi-live cleanup reported an error: first='%s' second='%s'\n",
        first->LastError().c_str(),
        second->LastError().c_str());
      ok = false;
    }

    if (ok) {
      std::printf(
        "multi-live smoke passed: independent windows, navigation, and cleanup\n");
    }
    return ok ? 0 : 1;
  }
}
