#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace pptbridge {

class PresentationDocument;

enum class RegisteredSourceKind {
  Slide,
  Presenter,
};

class Registry {
public:
  static Registry &Instance();

  std::shared_ptr<PresentationDocument> Acquire(const std::string &pptx_path);
  void SetActive(const std::shared_ptr<PresentationDocument> &document);
  std::shared_ptr<PresentationDocument> Active() const;
  void AttachSource(void *token, const std::string &pptx_path, RegisteredSourceKind kind);
  void DetachSource(void *token);
  size_t CountSources(const std::string &pptx_path, RegisteredSourceKind kind) const;
  std::vector<void *> SourceTokens(const std::string &pptx_path, RegisteredSourceKind kind) const;

private:
  Registry() = default;

  struct RegisteredSource {
    std::string path;
    RegisteredSourceKind kind = RegisteredSourceKind::Slide;
  };

  mutable std::mutex mutex_;
  std::unordered_map<std::string, std::weak_ptr<PresentationDocument>> documents_;
  std::unordered_map<void *, RegisteredSource> sources_;
  std::weak_ptr<PresentationDocument> active_;
};

}  // namespace pptbridge
