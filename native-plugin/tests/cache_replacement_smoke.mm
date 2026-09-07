#include "../src/presentation_document.hpp"

#import <Foundation/Foundation.h>

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <thread>

namespace fs = std::filesystem;
using pptbridge::PresentationDocument;

namespace {

void WaitForLoad(const std::shared_ptr<PresentationDocument> &document)
{
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(120);
  while (!document->IsLoaded() || document->IsLoading()) {
    if (!document->LastError().empty()) {
      throw std::runtime_error(document->LastError());
    }
    if (std::chrono::steady_clock::now() > deadline) {
      throw std::runtime_error("load timed out");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
}

std::shared_ptr<PresentationDocument> Load(const fs::path &path)
{
  auto document = std::make_shared<PresentationDocument>(path.string());
  document->SetPresenterAssetsWanted(true);
  document->EnsureLoadingAsync();
  WaitForLoad(document);
  return document;
}

fs::path CacheFor(const fs::path &path)
{
  return fs::path(NSHomeDirectory().UTF8String) / "Library/Application Support/PPTBridge SK/cache" /
    std::to_string(std::hash<std::string>{}(path.string()));
}

} // namespace

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc != 3) {
      std::fprintf(stderr, "usage: %s first.pptx different-slide-count.pptx\n", argv[0]);
      return 2;
    }
    const auto root = fs::temp_directory_path() /
      ("pptbridge-cache-replacement-" + std::string(NSUUID.UUID.UUIDString.UTF8String));
    try {
      fs::create_directories(root);
      const auto current = root / "current.pptx";
      const auto reference = root / "reference.pptx";
      fs::copy_file(argv[1], current);
      fs::copy_file(argv[2], reference);
      auto document = Load(current);
      const auto old_count = document->SlideCount();
      const auto expected_count = Load(reference)->SlideCount();
      if (old_count == expected_count) {
        throw std::runtime_error("fixtures must have different slide counts");
      }
      const auto original_time = fs::last_write_time(current);
      fs::copy_file(reference, current, fs::copy_options::overwrite_existing);
      fs::last_write_time(current, original_time - std::chrono::hours(24));
      document->ReloadAsync();
      WaitForLoad(document);
      std::printf("same-path replacement: old=%zu expected=%zu actual=%zu\n",
        old_count, expected_count, document->SlideCount());
      if (document->SlideCount() != expected_count) {
        throw std::runtime_error("replaced PPTX reused stale cached PDF");
      }
      const auto start = std::chrono::steady_clock::now();
      const auto cache = CacheFor(current);
      const auto pdf_time = fs::last_write_time(cache / "deck.pdf");
      const auto manifest_time = fs::last_write_time(cache / "deck-cache.json");
      document->ReloadAsync();
      WaitForLoad(document);
      std::printf("unchanged cached reload: %lld ms\n",
        std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - start).count());
      if (document->SlideCount() != expected_count) {
        throw std::runtime_error("cached reload changed slide count");
      }
      if (fs::last_write_time(cache / "deck.pdf") != pdf_time ||
          fs::last_write_time(cache / "deck-cache.json") != manifest_time) {
        throw std::runtime_error("unchanged reload unnecessarily exported again");
      }

      std::ofstream(cache / "deck.pdf", std::ios::trunc) << "truncated cached PDF";
      document->ReloadAsync();
      WaitForLoad(document);
      if (document->SlideCount() != expected_count) {
        throw std::runtime_error("corrupt cached PDF did not recover");
      }
      std::puts("corrupt cached PDF: regenerated successfully");

      std::ofstream(cache / "deck-cache.json", std::ios::trunc) << "[1,2,3]";
      document->ReloadAsync();
      WaitForLoad(document);
      if (document->SlideCount() != expected_count) {
        throw std::runtime_error("invalid cache manifest did not recover");
      }
      std::puts("invalid cache manifest: regenerated successfully");

      const auto legacy = current.parent_path() / ".pptbridge-sk-cache" / cache.filename();
      fs::create_directories(legacy);
      fs::rename(cache / "deck.pdf", legacy / "deck.pdf");
      fs::rename(cache / "deck-cache.json", legacy / "deck-cache.json");
      document->ReloadAsync();
      WaitForLoad(document);
      if (document->SlideCount() != expected_count || !fs::exists(cache / "deck-cache.json")) {
        throw std::runtime_error("verified legacy cache was not migrated");
      }
      std::puts("verified legacy cache: migrated successfully");
      fs::remove_all(CacheFor(current));
      fs::remove_all(CacheFor(reference));
      fs::remove_all(root);
      return 0;
    } catch (const std::exception &error) {
      std::fprintf(stderr, "%s\n", error.what());
      fs::remove_all(root);
      return 1;
    }
  }
}
