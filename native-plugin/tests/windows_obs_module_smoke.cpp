#include <obs.h>

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <string>
#include <thread>

namespace fs = std::filesystem;

namespace {

std::string Utf8(const fs::path &path)
{
  const auto value = path.u8string();
  return {reinterpret_cast<const char *>(value.data()), value.size()};
}

bool CheckSource(const char *id, const fs::path &pdf)
{
  const auto file = Utf8(pdf);
  const auto missing_deck = Utf8(pdf.parent_path() / L"missing deck.pdf");
  const auto missing_background = Utf8(pdf.parent_path() / L"missing background.png");
  auto *settings = obs_data_create();
  obs_data_set_string(settings, "pptx_path", missing_deck.c_str());
  obs_data_set_string(settings, "presenter_background_image_path", missing_background.c_str());
  obs_data_set_bool(settings, "use_live_powerpoint", false);
  auto *source = obs_source_create_private(id, id, settings);
  obs_data_release(settings);
  if (!source) {
    return false;
  }

  auto *files = obs_source_get_missing_files(source);
  bool deck_reported = false;
  bool background_reported = false;
  for (size_t index = 0; index < obs_missing_files_count(files); ++index) {
    auto *entry = obs_missing_files_get_file(files, static_cast<int>(index));
    const std::string path = obs_missing_file_get_path(entry);
    if (path == missing_deck) {
      deck_reported = true;
      obs_missing_file_issue_callback(entry, file.c_str());
    } else if (path == missing_background) {
      background_reported = true;
      obs_missing_file_issue_callback(entry, "");
    }
  }
  obs_missing_files_destroy(files);
  settings = obs_source_get_settings(source);
  const bool relinked =
    std::string(obs_data_get_string(settings, "pptx_path")) == file &&
    std::string(obs_data_get_string(settings, "presenter_background_image_path")).empty();
  obs_data_release(settings);
  files = obs_source_get_missing_files(source);
  const bool no_missing_files = obs_missing_files_count(files) == 0;
  obs_missing_files_destroy(files);
  // Allow the private source's initial missing-file worker to finish before
  // libobs unloads the DLL. Headless libobs has no graphics or video loop.
  std::this_thread::sleep_for(std::chrono::milliseconds(200));
  obs_source_release(source);
  const bool passed = deck_reported && background_reported && relinked && no_missing_files;
  std::printf("%s: missing deck, missing background, Unicode relink and clear: %s\n",
              id, passed ? "PASS" : "FAIL");
  return passed;
}

}  // namespace

int wmain(int argc, wchar_t **argv)
{
  if (argc != 4 || !fs::is_regular_file(argv[3])) {
    std::fprintf(stderr, "usage: windows_obs_module_smoke plugin.dll data-dir input.pdf\n");
    return 2;
  }

  if (!obs_startup("en-US", nullptr, nullptr)) {
    return 2;
  }

  auto *module = static_cast<obs_module_t *>(nullptr);
  const auto library = Utf8(argv[1]);
  const auto data = Utf8(argv[2]);
  const int result = obs_open_module(&module, library.c_str(), data.c_str());
  if (result != MODULE_SUCCESS || !obs_init_module(module)) {
    std::fprintf(stderr, "OBS module load failed: %d\n", result);
    obs_shutdown();
    return 2;
  }

  const bool slide = CheckSource("pptbridge_slide_source", argv[3]);
  const bool presenter = CheckSource("pptbridge_presenter_source", argv[3]);
  obs_shutdown();
  return slide && presenter ? 0 : 1;
}
