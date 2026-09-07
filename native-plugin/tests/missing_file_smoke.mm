#include "../src/source_shared.hpp"

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <string>
#include <thread>

namespace pptbridge {
obs_source_info *pptbridge_slide_source_info();
obs_source_info *pptbridge_presenter_source_info();
}

static bool WaitForSettled(obs_source_t *source)
{
  auto *context = static_cast<pptbridge::SourceContext *>(obs_obj_get_data(source));
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (context->document && context->document->IsLoading()) {
    if (std::chrono::steady_clock::now() > deadline) {
      return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  return true;
}

static bool CheckSource(const char *kind, const char *pdf_path)
{
  const std::string missing = "/tmp/pptbridge-missing-file-smoke-absent/deck.pptx";
  const std::string background = "/tmp/pptbridge-missing-file-smoke-absent/logo.png";
  if (std::filesystem::exists(missing) || std::filesystem::exists(background)) {
    return false;
  }
  obs_data_t *settings = obs_data_create();
  obs_data_set_string(settings, "pptx_path", missing.c_str());
  obs_data_set_string(settings, "presenter_background_image_path", background.c_str());
  obs_data_set_bool(settings, "use_live_powerpoint", false);
  obs_source_t *source = obs_source_create_private(kind, kind, settings);
  obs_data_release(settings);
  if (!source || !WaitForSettled(source)) {
    return false;
  }

  obs_properties_t *properties = obs_source_properties(source);
  auto *issue = obs_properties_get(properties, "pptbridge_input_issue");
  bool ok = issue && obs_property_visible(issue) &&
            std::string(obs_property_description(issue)).find("use Browse") != std::string::npos;
  auto *status = obs_properties_get(properties, "pptbridge_operator_status");
  ok = ok && status && std::string(obs_property_description(status)).find("presentation unavailable") != std::string::npos;
  obs_properties_destroy(properties);

  obs_missing_files_t *files = obs_source_get_missing_files(source);
  ok = ok && obs_missing_files_count(files) == 2;
  for (size_t index = 0; index < obs_missing_files_count(files); ++index) {
    auto *file = obs_missing_files_get_file(files, static_cast<int>(index));
    if (std::string(obs_missing_file_get_path(file)) == missing) {
      obs_missing_file_issue_callback(file, pdf_path);
    } else {
      // Clearing an optional missing background must not clear the presentation.
      obs_missing_file_issue_callback(file, "");
    }
  }
  obs_missing_files_destroy(files);
  // Headless libobs has no video loop to apply its deferred source update.
  settings = obs_source_get_settings(source);
  pptbridge::source_update(static_cast<pptbridge::SourceContext *>(obs_obj_get_data(source)), settings);
  obs_data_release(settings);
  ok = WaitForSettled(source) && ok;
  settings = obs_source_get_settings(source);
  ok = ok && std::string(obs_data_get_string(settings, "pptx_path")) == pdf_path &&
       std::string(obs_data_get_string(settings, "presenter_background_image_path")).empty();
  obs_data_release(settings);
  files = obs_source_get_missing_files(source);
  ok = ok && obs_missing_files_count(files) == 0;
  obs_missing_files_destroy(files);
  auto *context = static_cast<pptbridge::SourceContext *>(obs_obj_get_data(source));
  ok = ok && context->document && context->document->IsLoaded() && context->document->SlideCount() > 0;
  properties = obs_source_properties(source);
  issue = obs_properties_get(properties, "pptbridge_input_issue");
  ok = ok && issue && !obs_property_visible(issue);
  obs_properties_destroy(properties);
  std::printf("%s: missing file reporting, relink, optional background clear, loaded PDF, error clear: %s\n",
              kind, ok ? "PASS" : "FAIL");
  obs_source_release(source);
  return ok;
}

int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc != 2 || !std::filesystem::is_regular_file(argv[1])) {
      std::fprintf(stderr, "usage: missing_file_smoke /path/to/valid.pdf\n");
      return 2;
    }
    if (!obs_startup("en-US", nullptr, nullptr)) {
      return 2;
    }
    obs_register_source(pptbridge::pptbridge_slide_source_info());
    obs_register_source(pptbridge::pptbridge_presenter_source_info());
    const bool slide_ok = CheckSource("pptbridge_slide_source", argv[1]);
    const bool presenter_ok = CheckSource("pptbridge_presenter_source", argv[1]);
    obs_shutdown();
    return slide_ok && presenter_ok ? 0 : 1;
  }
}
