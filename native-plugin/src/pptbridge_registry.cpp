#include "pptbridge_registry.hpp"

#include "presentation_document.hpp"

namespace pptbridge {

Registry &Registry::Instance()
{
  static Registry instance;
  return instance;
}

std::shared_ptr<PresentationDocument> Registry::Acquire(const std::string &pptx_path)
{
  if (pptx_path.empty()) {
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  auto existing = documents_[pptx_path].lock();
  if (existing) {
    return existing;
  }

  auto created = std::make_shared<PresentationDocument>(pptx_path);
  documents_[pptx_path] = created;
  return created;
}

void Registry::SetActive(const std::shared_ptr<PresentationDocument> &document)
{
  std::lock_guard<std::mutex> lock(mutex_);
  active_ = document;
}

std::shared_ptr<PresentationDocument> Registry::Active() const
{
  std::lock_guard<std::mutex> lock(mutex_);
  return active_.lock();
}

}  // namespace pptbridge

