#include "../src/presentation_document.hpp"

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <thread>

using pptbridge::PresentationDocument;

namespace fs = std::filesystem;

namespace {

bool ExpectRejected(const std::string &path, const std::string &expected_error)
{
  auto document = std::make_shared<PresentationDocument>(path);
  document->EnsureLoadingAsync();

  const auto start = std::chrono::steady_clock::now();
  while (std::chrono::steady_clock::now() - start < std::chrono::seconds(5)) {
    if (document->IsLoaded()) {
      std::fprintf(stderr, "invalid input loaded unexpectedly: %s\n", path.c_str());
      return false;
    }

    const auto error = document->LastError();
    if (!error.empty()) {
      if (error.find(expected_error) == std::string::npos) {
        std::fprintf(stderr, "unexpected error for %s: %s\n", path.c_str(), error.c_str());
        return false;
      }
      std::printf("rejected: %s -> %s\n", path.c_str(), error.c_str());
      return true;
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  std::fprintf(stderr, "invalid input rejection timed out: %s\n", path.c_str());
  return false;
}

} // namespace

int main()
{
  @autoreleasepool {
    const auto root = fs::temp_directory_path() / "pptbridge-invalid-input-smoke";
    std::error_code error;
    fs::remove_all(root, error);
    fs::create_directories(root, error);
    if (error) {
      std::fprintf(stderr, "could not create test directory: %s\n", error.message().c_str());
      return 2;
    }

    const auto unsupported = root / "not-a-presentation.txt";
    const auto corrupt_pptx = root / "corrupt.pptx";
    const auto corrupt_pdf = root / "corrupt.pdf";
    {
      std::ofstream output(unsupported);
      output << "not a presentation";
    }
    {
      std::ofstream output(corrupt_pptx);
      output << "not a ZIP package";
    }
    {
      std::ofstream output(corrupt_pdf);
      output << "not a PDF document";
    }

    const bool unsupported_ok = ExpectRejected(unsupported.string(), "supports only .pptx and .pdf");
    const bool corrupt_ok = ExpectRejected(corrupt_pptx.string(), "not a valid PowerPoint presentation");
    const bool corrupt_pdf_ok = ExpectRejected(corrupt_pdf.string(), "selected .pdf file could not be opened by PDFKit");
    const bool missing_ok = ExpectRejected((root / "missing.pptx").string(), "could not be found");
    const bool empty_ok = ExpectRejected("", "Choose a .pptx or .pdf");

    fs::remove_all(root, error);
    return unsupported_ok && corrupt_ok && corrupt_pdf_ok && missing_ok && empty_ok ? 0 : 1;
  }
}
