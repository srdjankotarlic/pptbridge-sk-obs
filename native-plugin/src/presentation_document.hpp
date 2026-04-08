#pragma once

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace pptbridge {

struct SlideMetadata {
  std::string title;
  std::string notes;
};

class PresentationDocument : public std::enable_shared_from_this<PresentationDocument> {
public:
  explicit PresentationDocument(std::string pptx_path);
  ~PresentationDocument();

  const std::string &Path() const;
  std::string Name() const;

  void EnsureLoadingAsync();
  void ReloadAsync();

  bool IsLoaded() const;
  bool IsLoading() const;
  std::string LastError() const;

  std::size_t SlideCount() const;
  std::size_t CurrentIndex() const;
  bool HasNext() const;
  bool HasPrevious() const;
  bool IsBlackScreen() const;

  void Next();
  void Previous();
  void First();
  void Last();
  void GoTo(std::size_t index);
  void ToggleBlackScreen();

  uint64_t StateVersion() const;
  uint64_t PresentationSeconds() const;

  bool RenderSlideBGRA(
    uint32_t width,
    uint32_t height,
    std::vector<uint8_t> &out_pixels,
    uint32_t &out_stride
  ) const;

  bool RenderPresenterBGRA(
    uint32_t width,
    uint32_t height,
    std::vector<uint8_t> &out_pixels,
    uint32_t &out_stride
  ) const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;

  void StartLoadIfNeeded(bool force_reload);
  void LoadOnWorker();
};

}  // namespace pptbridge

