#include "windows_pdf_renderer.hpp"

#ifdef _WIN32

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

namespace {

bool HasPngSignature(const fs::path &path)
{
  static constexpr uint8_t expected[] = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
  std::ifstream input(path, std::ios::binary);
  uint8_t actual[sizeof(expected)] = {};
  input.read(reinterpret_cast<char *>(actual), sizeof(actual));
  return input.gcount() == static_cast<std::streamsize>(sizeof(actual)) &&
         std::equal(std::begin(expected), std::end(expected), std::begin(actual));
}

}  // namespace

int wmain(int argc, wchar_t **argv)
{
  if (argc != 3) {
    std::wcerr << L"usage: pptbridge-windows-pdf-smoke.exe <input.pdf> <output-directory>\n";
    return 64;
  }

  const auto started = std::chrono::steady_clock::now();
  pptbridge::WindowsPdfRenderResult result;
  std::string error;
  if (!pptbridge::RenderWindowsPdfPages(argv[1], argv[2], 1920, 1080, result, error)) {
    std::cerr << "ERROR=" << error << "\n";
    return 2;
  }

  if (result.image_paths.empty() || result.first_page_aspect_ratio < 0.05 ||
      result.first_page_aspect_ratio > 20.0) {
    std::cerr << "ERROR=renderer returned invalid page metadata\n";
    return 3;
  }

  for (const auto &image_path : result.image_paths) {
    if (!fs::is_regular_file(fs::path(image_path)) || !HasPngSignature(fs::path(image_path))) {
      std::wcerr << L"ERROR=invalid rendered PNG: " << image_path << L"\n";
      return 4;
    }
  }

  const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
    std::chrono::steady_clock::now() - started).count();
  std::cout << "PAGES=" << result.image_paths.size()
            << "|ASPECT=" << result.first_page_aspect_ratio
            << "|ELAPSED_MS=" << elapsed_ms << "\n";
  return 0;
}

#endif  // _WIN32
