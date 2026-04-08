#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace pptbridge {

class PresentationDocument;

class Registry {
public:
  static Registry &Instance();

  std::shared_ptr<PresentationDocument> Acquire(const std::string &pptx_path);
  void SetActive(const std::shared_ptr<PresentationDocument> &document);
  std::shared_ptr<PresentationDocument> Active() const;

private:
  Registry() = default;

  mutable std::mutex mutex_;
  std::unordered_map<std::string, std::weak_ptr<PresentationDocument>> documents_;
  std::weak_ptr<PresentationDocument> active_;
};

}  // namespace pptbridge

