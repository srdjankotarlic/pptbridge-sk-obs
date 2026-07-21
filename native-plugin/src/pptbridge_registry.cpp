#include "pptbridge_registry.hpp"

#include "presentation_document.hpp"

#ifdef _WIN32
#include <algorithm>
#include <cwctype>
#include <filesystem>
#endif

namespace pptbridge {

namespace {

std::string CanonicalRegistryPath(const std::string &path)
{
#ifdef _WIN32
  if (path.empty()) {
    return {};
  }

  namespace fs = std::filesystem;
  std::error_code ec;
  fs::path normalized = fs::absolute(fs::u8path(path), ec);
  if (ec) {
    normalized = fs::u8path(path);
    ec.clear();
  }
  normalized = normalized.lexically_normal();

  const fs::path canonical = fs::weakly_canonical(normalized, ec);
  if (!ec && !canonical.empty()) {
    normalized = canonical;
  }
  return normalized.u8string();
#else
  return path;
#endif
}

std::string RegistryPathKey(const std::string &path)
{
  std::string canonical = CanonicalRegistryPath(path);
#ifdef _WIN32
  std::wstring wide = std::filesystem::u8path(canonical).wstring();
  std::transform(wide.begin(), wide.end(), wide.begin(), [](wchar_t ch) {
    return static_cast<wchar_t>(std::towlower(ch));
  });
  canonical = std::filesystem::path(wide).u8string();
#endif
  return canonical;
}

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

  const std::string canonical_path = CanonicalRegistryPath(pptx_path);
  const std::string registry_key = RegistryPathKey(canonical_path);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    RemoveExpiredDocuments(documents_);
    auto found = documents_.find(registry_key);
    if (found != documents_.end()) {
      if (auto existing = found->second.lock()) {
        return existing;
      }
      documents_.erase(found);
    }
  }

  auto created = std::make_shared<PresentationDocument>(canonical_path);
  std::lock_guard<std::mutex> lock(mutex_);
  RemoveExpiredDocuments(documents_);
  auto found = documents_.find(registry_key);
  if (found != documents_.end()) {
    if (auto existing = found->second.lock()) {
      return existing;
    }
  }

  documents_[registry_key] = created;
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

  sources_[token] = RegisteredSource{ RegistryPathKey(pptx_path), kind };
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

  const std::string registry_key = RegistryPathKey(pptx_path);

  std::lock_guard<std::mutex> lock(mutex_);
  size_t count = 0;
  for (const auto &[token, source] : sources_) {
    (void)token;
    if (source.kind == kind && source.path == registry_key) {
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

  const std::string registry_key = RegistryPathKey(pptx_path);

  std::lock_guard<std::mutex> lock(mutex_);
  for (const auto &[token, source] : sources_) {
    if (source.kind == kind && source.path == registry_key) {
      tokens.push_back(token);
    }
  }
  return tokens;
}

}  // namespace pptbridge
