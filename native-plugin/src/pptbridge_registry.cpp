#include "pptbridge_registry.hpp"

#include "presentation_document.hpp"

namespace pptbridge {

namespace {

void RemoveExpiredDocuments(std::unordered_map<std::string, std::weak_ptr<PresentationDocument>> &documents)
{
  for (auto it = documents.begin(); it != documents.end();) {
    if (it->second.expired()) {
      it = documents.erase(it);
    } else {
      ++it;
    }
  }
}

}  // namespace

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

  {
    std::lock_guard<std::mutex> lock(mutex_);
    RemoveExpiredDocuments(documents_);
    auto found = documents_.find(pptx_path);
    if (found != documents_.end()) {
      if (auto existing = found->second.lock()) {
        return existing;
      }
      documents_.erase(found);
    }
  }

  auto created = std::make_shared<PresentationDocument>(pptx_path);
  std::lock_guard<std::mutex> lock(mutex_);
  RemoveExpiredDocuments(documents_);
  auto found = documents_.find(pptx_path);
  if (found != documents_.end()) {
    if (auto existing = found->second.lock()) {
      return existing;
    }
  }

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

void Registry::AttachSource(void *token, const std::string &pptx_path, RegisteredSourceKind kind)
{
  if (!token) {
    return;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  if (pptx_path.empty()) {
    sources_.erase(token);
    return;
  }

  sources_[token] = RegisteredSource{ pptx_path, kind };
}

void Registry::DetachSource(void *token)
{
  if (!token) {
    return;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  sources_.erase(token);
}

size_t Registry::CountSources(const std::string &pptx_path, RegisteredSourceKind kind) const
{
  if (pptx_path.empty()) {
    return 0;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  size_t count = 0;
  for (const auto &[token, source] : sources_) {
    (void)token;
    if (source.kind == kind && source.path == pptx_path) {
      count += 1;
    }
  }
  return count;
}

std::vector<void *> Registry::SourceTokens(const std::string &pptx_path, RegisteredSourceKind kind) const
{
  std::vector<void *> tokens;
  if (pptx_path.empty()) {
    return tokens;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  for (const auto &[token, source] : sources_) {
    if (source.kind == kind && source.path == pptx_path) {
      tokens.push_back(token);
    }
  }
  return tokens;
}

}  // namespace pptbridge
