#pragma once

#ifdef _WIN32

#include <cstdint>
#include <string>
#include <vector>

namespace pptbridge {

struct WindowsPdfRenderResult {
  std::vector<std::wstring> image_paths;
  double first_page_aspect_ratio = 0.0;
};

bool RenderWindowsPdfPages(
  const std::wstring &pdf_path,
  const std::wstring &output_directory,
  uint32_t max_width,
  uint32_t max_height,
  WindowsPdfRenderResult &out_result,
  std::string &out_error);

}  // namespace pptbridge

#endif  // _WIN32
