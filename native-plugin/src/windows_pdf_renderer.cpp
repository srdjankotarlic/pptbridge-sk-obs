#include "windows_pdf_renderer.hpp"

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.UI.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <mutex>
#include <sstream>
#include <system_error>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace pptbridge {

namespace {

constexpr uint32_t kMaxPdfPages = 5000;
constexpr size_t kRetainedPdfGenerations = 3;
constexpr DWORD kGlobalPdfRenderTimeoutMs = 10 * 60 * 1000;
constexpr wchar_t kGlobalPdfRenderMutexName[] = L"Local\\PPTBridgeSK-WindowsPdfRender-v1";

class WinRtApartment final {
public:
  WinRtApartment()
  {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      initialized_ = true;
    } catch (const winrt::hresult_error &error) {
      if (error.code() != RPC_E_CHANGED_MODE) {
        throw;
      }
    }
  }

  ~WinRtApartment()
  {
    if (initialized_) {
      winrt::uninit_apartment();
    }
  }

  WinRtApartment(const WinRtApartment &) = delete;
  WinRtApartment &operator=(const WinRtApartment &) = delete;

private:
  bool initialized_ = false;
};

std::wstring PageFileName(uint32_t page_number)
{
  std::wostringstream name;
  name << L"page-" << std::setw(5) << std::setfill(L'0') << page_number << L".png";
  return name.str();
}

std::mutex &PdfRenderMutex()
{
  static std::mutex mutex;
  return mutex;
}

std::wstring PdfGenerationName()
{
  static std::atomic<uint64_t> counter{0};
  const auto tick = static_cast<uint64_t>(
    std::chrono::steady_clock::now().time_since_epoch().count());
  std::wostringstream name;
  name << L"pdf-generation-" << GetCurrentProcessId() << L"-" << std::hex << tick << L"-"
       << counter.fetch_add(1, std::memory_order_relaxed);
  return name.str();
}

class ScopedDirectoryCleanup final {
public:
  explicit ScopedDirectoryCleanup(fs::path path) : path_(std::move(path)) {}
  ~ScopedDirectoryCleanup()
  {
    if (active_) {
      std::error_code error;
      fs::remove_all(path_, error);
    }
  }

  void Release() { active_ = false; }

private:
  fs::path path_;
  bool active_ = true;
};

class GlobalPdfRenderLock final {
public:
  GlobalPdfRenderLock()
  {
    mutex_ = CreateMutexW(nullptr, FALSE, kGlobalPdfRenderMutexName);
    if (!mutex_) {
      return;
    }
    const DWORD wait_result = WaitForSingleObject(mutex_, kGlobalPdfRenderTimeoutMs);
    acquired_ = wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED;
  }

  ~GlobalPdfRenderLock()
  {
    if (acquired_) {
      ReleaseMutex(mutex_);
    }
    if (mutex_) {
      CloseHandle(mutex_);
    }
  }

  bool Acquired() const { return acquired_; }

  GlobalPdfRenderLock(const GlobalPdfRenderLock &) = delete;
  GlobalPdfRenderLock &operator=(const GlobalPdfRenderLock &) = delete;

private:
  HANDLE mutex_ = nullptr;
  bool acquired_ = false;
};

void CleanupStalePdfGenerations(const fs::path &root)
{
  struct Generation {
    fs::path path;
    fs::file_time_type modified;
  };

  std::vector<Generation> generations;
  std::error_code error;
  for (fs::directory_iterator iterator(root, error), end; !error && iterator != end; iterator.increment(error)) {
    if (!iterator->is_directory(error) || error) {
      error.clear();
      continue;
    }
    const auto name = iterator->path().filename().wstring();
    if (name.rfind(L"pdf-generation-", 0) != 0) {
      continue;
    }
    const auto modified = iterator->last_write_time(error);
    if (!error) {
      generations.push_back({iterator->path(), modified});
    }
    error.clear();
  }

  std::sort(generations.begin(), generations.end(), [](const Generation &left, const Generation &right) {
    return left.modified > right.modified;
  });
  // Fresh generations can still be rendered by another OBS process.
  const auto cutoff = fs::file_time_type::clock::now() - std::chrono::hours(24);
  for (size_t index = kRetainedPdfGenerations; index < generations.size(); ++index) {
    if (generations[index].modified < cutoff) {
      fs::remove_all(generations[index].path, error);
      error.clear();
    }
  }
}

bool WriteBytesAtomically(const fs::path &destination, const std::vector<uint8_t> &bytes, std::string &out_error)
{
  static std::atomic<uint64_t> temporary_counter{0};
  const fs::path temporary = destination.wstring() + L".tmp-" +
    std::to_wstring(GetCurrentProcessId()) + L"-" +
    std::to_wstring(temporary_counter.fetch_add(1, std::memory_order_relaxed));
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output) {
      out_error = "Could not create a rendered PDF page in the PPTBridge cache.";
      return false;
    }
    output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    output.flush();
    if (!output) {
      out_error = "Could not finish writing a rendered PDF page to the PPTBridge cache.";
      return false;
    }
  }

  if (!MoveFileExW(
        temporary.c_str(),
        destination.c_str(),
        MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    std::error_code error;
    fs::remove(temporary, error);
    out_error = "Could not finalize a rendered PDF page in the PPTBridge cache.";
    return false;
  }
  return true;
}

bool CopyStreamToBytes(
  const winrt::Windows::Storage::Streams::InMemoryRandomAccessStream &stream,
  std::vector<uint8_t> &out_bytes,
  std::string &out_error)
{
  const uint64_t size = stream.Size();
  if (size == 0 || size > static_cast<uint64_t>(std::numeric_limits<uint32_t>::max())) {
    out_error = "Windows returned an empty or oversized bitmap while rendering a PDF page.";
    return false;
  }

  stream.Seek(0);
  winrt::Windows::Storage::Streams::DataReader reader(stream.GetInputStreamAt(0));
  const uint32_t expected = static_cast<uint32_t>(size);
  const uint32_t loaded = reader.LoadAsync(expected).get();
  if (loaded != expected) {
    out_error = "Windows returned an incomplete bitmap while rendering a PDF page.";
    return false;
  }

  out_bytes.resize(expected);
  reader.ReadBytes(out_bytes);
  return true;
}

}  // namespace

bool RenderWindowsPdfPages(
  const std::wstring &pdf_path,
  const std::wstring &output_directory,
  uint32_t max_width,
  uint32_t max_height,
  WindowsPdfRenderResult &out_result,
  std::string &out_error)
{
  out_result = {};
  out_error.clear();

  if (pdf_path.empty() || max_width == 0 || max_height == 0) {
    out_error = "The PDF path or render size is invalid.";
    return false;
  }

  std::lock_guard<std::mutex> render_lock(PdfRenderMutex());
  GlobalPdfRenderLock global_render_lock;
  if (!global_render_lock.Acquired()) {
    out_error = "Timed out waiting for another Windows PDF render to finish.";
    return false;
  }

  std::error_code directory_error;
  const fs::path output_root(output_directory);
  fs::create_directories(output_root, directory_error);
  if (directory_error) {
    out_error = "Could not create the Windows PDF cache directory.";
    return false;
  }

  const fs::path generation_directory = output_root / PdfGenerationName();
  fs::create_directories(generation_directory, directory_error);
  if (directory_error) {
    out_error = "Could not create a Windows PDF cache generation.";
    return false;
  }
  ScopedDirectoryCleanup generation_cleanup(generation_directory);

  try {
    WinRtApartment apartment;
    const auto file = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(pdf_path).get();
    const auto document = winrt::Windows::Data::Pdf::PdfDocument::LoadFromFileAsync(file).get();
    const uint32_t page_count = document.PageCount();
    if (page_count == 0) {
      out_error = "The selected PDF contains no pages.";
      return false;
    }
    if (page_count > kMaxPdfPages) {
      out_error = "The selected PDF contains too many pages for a live presentation.";
      return false;
    }

    out_result.image_paths.reserve(page_count);
    for (uint32_t page_index = 0; page_index < page_count; ++page_index) {
      const auto page = document.GetPage(page_index);
      const auto size = page.Size();
      if (size.Width <= 0.0f || size.Height <= 0.0f ||
          !std::isfinite(size.Width) || !std::isfinite(size.Height)) {
        out_error = "Windows reported an invalid page size while rendering the PDF.";
        return false;
      }

      const double aspect_ratio = static_cast<double>(size.Width) / static_cast<double>(size.Height);
      if (page_index == 0) {
        out_result.first_page_aspect_ratio = aspect_ratio;
      }

      const double scale = std::min(
        static_cast<double>(max_width) / static_cast<double>(size.Width),
        static_cast<double>(max_height) / static_cast<double>(size.Height));
      const uint32_t destination_width = std::max<uint32_t>(
        1,
        static_cast<uint32_t>(std::llround(static_cast<double>(size.Width) * scale)));
      const uint32_t destination_height = std::max<uint32_t>(
        1,
        static_cast<uint32_t>(std::llround(static_cast<double>(size.Height) * scale)));

      winrt::Windows::Data::Pdf::PdfPageRenderOptions options;
      options.DestinationWidth(destination_width);
      options.DestinationHeight(destination_height);
      options.BackgroundColor(winrt::Windows::UI::Colors::White());
      options.BitmapEncoderId(winrt::Windows::Graphics::Imaging::BitmapEncoder::PngEncoderId());
      options.IsIgnoringHighContrast(true);

      winrt::Windows::Storage::Streams::InMemoryRandomAccessStream stream;
      page.RenderToStreamAsync(stream, options).get();

      std::vector<uint8_t> bytes;
      if (!CopyStreamToBytes(stream, bytes, out_error)) {
        return false;
      }

      const fs::path page_path = generation_directory / PageFileName(page_index + 1);
      if (!WriteBytesAtomically(page_path, bytes, out_error)) {
        return false;
      }
      out_result.image_paths.push_back(page_path.wstring());
    }

    generation_cleanup.Release();
    CleanupStalePdfGenerations(output_root);
    return true;
  } catch (const winrt::hresult_error &) {
    out_error =
      "Windows could not open or render the selected PDF. The file may be damaged or password-protected; "
      "password-protected PDFs are not supported.";
    return false;
  } catch (const std::exception &error) {
    out_error = std::string("Windows PDF rendering failed: ") + error.what();
    return false;
  }
}

}  // namespace pptbridge

#endif  // _WIN32
