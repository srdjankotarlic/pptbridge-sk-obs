#include "source_shared.hpp"

#include <filesystem>

namespace pptbridge {

obs_missing_files_t *source_missing_files(void *data)
{
  auto *context = static_cast<SourceContext *>(data);
  obs_missing_files_t *files = obs_missing_files_create();
  if (!context || !context->source) {
    return files;
  }

  obs_data_t *settings = obs_source_get_settings(context->source);
  for (const char *key : {"pptx_path", "presenter_background_image_path"}) {
    const std::string path = obs_data_get_string(settings, key);
    std::error_code error;
    if (path.empty() || std::filesystem::is_regular_file(std::filesystem::u8path(path), error)) {
      continue;
    }
    const auto replace = [](void *source_data, const char *new_path, void *key_data) {
      auto *source_context = static_cast<SourceContext *>(source_data);
      if (!source_context || !source_context->source || !new_path) {
        return;
      }
      obs_data_t *updated = obs_source_get_settings(source_context->source);
      obs_data_set_string(updated, static_cast<const char *>(key_data), new_path);
      obs_source_update(source_context->source, updated);
      obs_data_release(updated);
      obs_source_update_properties(source_context->source);
    };
    obs_missing_files_add_file(files, obs_missing_file_create(
      path.c_str(), replace, OBS_MISSING_FILE_SOURCE, context->source, const_cast<char *>(key)));
  }
  obs_data_release(settings);
  return files;
}

}  // namespace pptbridge
