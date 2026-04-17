#import "presentation_document.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

#include <obs-module.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <filesystem>
#include <sstream>
#include <thread>
#include <unordered_map>

namespace fs = std::filesystem;

namespace pptbridge {

namespace {

using Clock = std::chrono::steady_clock;

NSString *ToNSString(const std::string &value)
{
  return [NSString stringWithUTF8String:value.c_str()];
}

std::string ToStdString(NSString *value)
{
  return value ? std::string(value.UTF8String) : std::string();
}

NSString *JoinLines(NSArray<NSString *> *lines)
{
  return [lines componentsJoinedByString:@"\n"];
}

NSString *ReadZipEntry(const std::string &pptx_path, const std::string &entry_path);
NSArray<NSXMLNode *> *XPath(NSXMLNode *node, NSString *query);

bool RunTask(
  NSString *launch_path,
  NSArray<NSString *> *arguments,
  std::string &std_out,
  std::string &std_err,
  int &exit_code)
{
  @autoreleasepool {
    std_out.clear();
    std_err.clear();
    exit_code = -1;

    if (!launch_path || launch_path.length == 0) {
      std_err = "Executable path is empty.";
      return false;
    }

    NSPipe *out_pipe = [NSPipe pipe];
    NSPipe *err_pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    task.arguments = arguments;
    task.standardOutput = out_pipe;
    task.standardError = err_pipe;

    if (@available(macOS 10.13, *)) {
      task.executableURL = [NSURL fileURLWithPath:launch_path];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      task.launchPath = launch_path;
#pragma clang diagnostic pop
    }

    @try {
      if (@available(macOS 10.13, *)) {
        NSError *launch_error = nil;
        if (![task launchAndReturnError:&launch_error]) {
          std_err = ToStdString(launch_error.localizedDescription ?: @"Unknown task launch error");
          return false;
        }
      } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [task launch];
#pragma clang diagnostic pop
      }
      [task waitUntilExit];
    } @catch (NSException *exception) {
      std_err = ToStdString(exception.reason ?: @"Unknown task launch error");
      return false;
    }

    NSData *stdout_data = [[out_pipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderr_data = [[err_pipe fileHandleForReading] readDataToEndOfFile];

    std_out = ToStdString([[NSString alloc] initWithData:stdout_data encoding:NSUTF8StringEncoding] ?: @"");
    std_err = ToStdString([[NSString alloc] initWithData:stderr_data encoding:NSUTF8StringEncoding] ?: @"");
    exit_code = task.terminationStatus;
    return true;
  }
}

std::string TrimWhitespace(const std::string &value)
{
  NSString *trimmed =
    [ToNSString(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ToStdString(trimmed);
}

std::string BuildTaskErrorMessage(const std::string &std_out, const std::string &std_err, int exit_code)
{
  std::string message = TrimWhitespace(!std_err.empty() ? std_err : std_out);
  if (message.empty()) {
    message = "Process failed.";
  }
  return message + " (exit " + std::to_string(exit_code) + ")";
}

bool WriteUtf8TextFile(NSString *path, NSString *content, std::string &out_error)
{
  NSError *error = nil;
  if ([content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    return true;
  }

  out_error = ToStdString(error.localizedDescription ?: @"Failed to write helper script.");
  return false;
}

std::string FindLibreOfficeBinary()
{
  static const std::string cached = []() -> std::string {
    const std::vector<std::string> candidates = {
      "/Applications/LibreOffice.app/Contents/MacOS/soffice",
      "/opt/homebrew/bin/soffice",
      "/usr/local/bin/soffice",
    };

    for (const auto &candidate : candidates) {
      if (fs::exists(candidate)) {
        return candidate;
      }
    }

    std::string std_out;
    std::string std_err;
    int exit_code = 0;
    RunTask(@"/usr/bin/which", @[ @"soffice" ], std_out, std_err, exit_code);
    if (exit_code == 0 && !std_out.empty()) {
      NSString *trimmed =
        [ToNSString(std_out) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      return ToStdString(trimmed);
    }

    return {};
  }();

  return cached;
}

std::string FindPowerPointBundle()
{
  static const std::string cached = []() -> std::string {
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithArray:@[
      @"/Applications/Microsoft PowerPoint.app",
      @"/Applications/PowerPoint.app",
    ]];

    NSString *user_applications =
      [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Microsoft PowerPoint.app"];
    [candidates addObject:user_applications];

    for (NSString *candidate in candidates) {
      if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
        return ToStdString(candidate);
      }
    }

    std::string std_out;
    std::string std_err;
    int exit_code = 0;
    RunTask(
      @"/usr/bin/mdfind",
      @[ @"kMDItemCFBundleIdentifier == 'com.microsoft.Powerpoint'" ],
      std_out,
      std_err,
      exit_code);
    if (exit_code != 0 || std_out.empty()) {
      return {};
    }

    NSArray<NSString *> *lines =
      [ToNSString(std_out) componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
      NSString *trimmed =
        [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (trimmed.length == 0) {
        continue;
      }
      if ([[NSFileManager defaultManager] fileExistsAtPath:trimmed]) {
        return ToStdString(trimmed);
      }
    }

    return {};
  }();

  return cached;
}

std::string DeckCacheHash(const std::string &pptx_path)
{
  std::stringstream stream;
  stream << std::hash<std::string>{}(pptx_path);
  return stream.str();
}

std::string LegacyCacheDirectoryForDeck(const std::string &pptx_path)
{
  const auto pptx_dir = fs::path(pptx_path).parent_path();
  if (pptx_dir.empty()) {
    return {};
  }

  return (pptx_dir / ".pptbridge-sk-cache" / DeckCacheHash(pptx_path)).string();
}

std::string CacheDirectoryForDeck(const std::string &pptx_path)
{
  const auto hash = DeckCacheHash(pptx_path);

  // On macOS 26+ (Tahoe) OBS - as a non-sandboxed app - can no longer
  // reliably read or write inside other apps' containers
  // (~/Library/Containers/...). fs::create_directories still reports
  // success there because the directory already exists, but follow-up
  // file I/O is silently blocked by TCC and PDFKit returns nil on
  // otherwise-valid PDFs. We therefore keep the cache inside OBS's own
  // Application Support directory by default and only fall back to
  // PowerPoint's container (legacy layout) if for some reason
  // Application Support is not writable. PowerPoint's AppleScript
  // "save as PDF" is still allowed to write into Application Support -
  // macOS will prompt the user the first time and remember the grant.
  auto app_support = fs::path(ToStdString(NSHomeDirectory())) / "Library" / "Application Support" / "PPTBridge SK" / "cache" / hash;
  std::error_code error;
  fs::create_directories(app_support, error);
  if (!error) {
    return app_support.string();
  }

  auto powerpoint_container = fs::path(ToStdString(NSHomeDirectory())) /
    "Library/Containers/com.microsoft.Powerpoint/Data/Library/Caches/com.microsoft.Powerpoint/PPTBridge-SK" / hash;
  error.clear();
  fs::create_directories(powerpoint_container, error);
  if (!error) {
    return powerpoint_container.string();
  }

  auto temp_dir = fs::path(ToStdString(NSTemporaryDirectory())) / "pptbridge-native" / hash;
  fs::create_directories(temp_dir, error);
  return temp_dir.string();
}

bool TryUseCachedPdf(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::string &out_pdf_path)
{
  std::error_code error;
  const auto cached_pdf = fs::path(cache_dir) / "deck.pdf";
  if (!fs::exists(cached_pdf, error) || error) {
    return false;
  }

  const auto pptx_time = fs::last_write_time(pptx_path, error);
  if (error) {
    return false;
  }

  const auto pdf_time = fs::last_write_time(cached_pdf, error);
  if (error) {
    return false;
  }

  if (pdf_time >= pptx_time) {
    out_pdf_path = cached_pdf.string();
    return true;
  }

  return false;
}

bool TryUseLegacyCachedPdf(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::string &out_pdf_path)
{
  const auto legacy_dir = LegacyCacheDirectoryForDeck(pptx_path);
  if (legacy_dir.empty() || legacy_dir == cache_dir) {
    return false;
  }

  std::string legacy_pdf_path;
  if (!TryUseCachedPdf(pptx_path, legacy_dir, legacy_pdf_path)) {
    return false;
  }

  std::error_code error;
  const auto target_pdf = fs::path(cache_dir) / "deck.pdf";
  fs::copy_file(legacy_pdf_path, target_pdf, fs::copy_options::overwrite_existing, error);
  if (error) {
    return false;
  }

  out_pdf_path = target_pdf.string();
  return true;
}

struct RelationshipInfo {
  std::string type;
  std::string target;
  bool external = false;
};

std::string ToLowerCopy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

bool StringContainsCaseInsensitive(const std::string &value, const std::string &needle)
{
  return ToLowerCopy(value).find(ToLowerCopy(needle)) != std::string::npos;
}

bool IsImageExtension(const std::string &extension)
{
  static const std::vector<std::string> kExtensions = {
    ".bmp",
    ".emf",
    ".gif",
    ".jpeg",
    ".jpg",
    ".png",
    ".svg",
    ".tif",
    ".tiff",
    ".wmf",
  };
  const auto lowered = ToLowerCopy(extension);
  return std::find(kExtensions.begin(), kExtensions.end(), lowered) != kExtensions.end();
}

bool IsVideoExtension(const std::string &extension)
{
  static const std::vector<std::string> kExtensions = {
    ".asf",
    ".avi",
    ".m4v",
    ".mkv",
    ".mov",
    ".mp4",
    ".mpeg",
    ".mpg",
    ".webm",
    ".wmv",
  };
  const auto lowered = ToLowerCopy(extension);
  return std::find(kExtensions.begin(), kExtensions.end(), lowered) != kExtensions.end();
}

bool IsAudioExtension(const std::string &extension)
{
  static const std::vector<std::string> kExtensions = {
    ".aac",
    ".aif",
    ".aiff",
    ".flac",
    ".m4a",
    ".mp3",
    ".ogg",
    ".wav",
    ".wma",
  };
  const auto lowered = ToLowerCopy(extension);
  return std::find(kExtensions.begin(), kExtensions.end(), lowered) != kExtensions.end();
}

std::string ResolveZipTarget(const std::string &base_entry, const std::string &target)
{
  auto base_dir = fs::path(base_entry).parent_path();
  auto resolved = (base_dir / fs::path(target)).lexically_normal();
  return resolved.generic_string();
}

NSString *AttributeByLocalName(NSXMLNode *node, NSString *local_name)
{
  if (![node isKindOfClass:[NSXMLElement class]]) {
    return nil;
  }

  for (NSXMLNode *attribute in [(NSXMLElement *)node attributes]) {
    if ([attribute.localName isEqualToString:local_name]) {
      return attribute.stringValue;
    }
  }

  return nil;
}

std::unordered_map<std::string, RelationshipInfo> ParseRelationships(const std::string &pptx_path, const std::string &rels_entry)
{
  std::unordered_map<std::string, RelationshipInfo> relationships;
  NSString *rels_xml = ReadZipEntry(pptx_path, rels_entry);
  if (rels_xml.length == 0) {
    return relationships;
  }

  NSError *error = nil;
  NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:rels_xml options:0 error:&error];
  if (error) {
    return relationships;
  }

  NSArray<NSXMLNode *> *nodes = XPath(document, @"//*[local-name()='Relationship']");
  for (NSXMLNode *node in nodes) {
    NSString *identifier = AttributeByLocalName(node, @"Id");
    NSString *type = AttributeByLocalName(node, @"Type");
    NSString *target = AttributeByLocalName(node, @"Target");
    NSString *target_mode = AttributeByLocalName(node, @"TargetMode");
    if (identifier.length == 0 || target.length == 0) {
      continue;
    }

    relationships[ToStdString(identifier)] = RelationshipInfo {
      ToStdString(type ?: @""),
      ToStdString(target),
      target_mode && [target_mode caseInsensitiveCompare:@"External"] == NSOrderedSame,
    };
  }

  return relationships;
}

bool ExtractZipEntryToFile(
  const std::string &pptx_path,
  const std::string &entry_path,
  const std::string &destination_root,
  std::string &out_file_path,
  std::string &out_error)
{
  auto destination = fs::path(destination_root) / fs::path(entry_path);
  std::error_code create_error;
  fs::create_directories(destination.parent_path(), create_error);
  if (fs::exists(destination, create_error) && !create_error) {
    std::error_code time_error;
    const auto source_time = fs::last_write_time(pptx_path, time_error);
    if (!time_error) {
      time_error.clear();
      const auto destination_time = fs::last_write_time(destination, time_error);
      if (!time_error && destination_time >= source_time) {
        out_file_path = destination.string();
        return true;
      }
    }
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool ok = RunTask(
    @"/usr/bin/unzip",
    @[ @"-qo", ToNSString(pptx_path), ToNSString(entry_path), @"-d", ToNSString(destination_root) ],
    std_out,
    std_err,
    exit_code);
  if (!ok || exit_code != 0 || !fs::exists(destination)) {
    out_error = BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  out_file_path = destination.string();
  return true;
}

bool ConvertPptxToPdfWithLibreOffice(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::string &out_pdf_path,
  std::string &out_error)
{
  if (pptx_path.empty()) {
    out_error = "Choose a .pptx file in source properties.";
    return false;
  }
  if (!fs::exists(pptx_path)) {
    out_error = "The selected .pptx file could not be found.";
    return false;
  }

  const auto soffice = FindLibreOfficeBinary();
  if (soffice.empty()) {
    out_error = "LibreOffice was not found. Install LibreOffice before using PPTBridge.";
    return false;
  }

  auto work_dir = fs::path(cache_dir) / "conversion";
  auto profile_dir = fs::path(cache_dir) / "lo-profile";
  fs::remove_all(work_dir);
  fs::remove_all(profile_dir);
  fs::create_directories(work_dir);
  fs::create_directories(profile_dir);

  NSString *profile_dir_ns = ToNSString(profile_dir.string());
  NSString *work_dir_ns = ToNSString(work_dir.string());
  NSString *pptx_path_ns = ToNSString(pptx_path);
  NSString *soffice_ns = ToNSString(soffice);
  NSURL *profile_url = profile_dir_ns ? [NSURL fileURLWithPath:profile_dir_ns isDirectory:YES] : nil;
  if (!profile_dir_ns || !work_dir_ns || !pptx_path_ns || !soffice_ns || !profile_url) {
    out_error = "One of the selected paths contains unsupported characters.";
    return false;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;

  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  [arguments addObject:[@"-env:UserInstallation=" stringByAppendingString:profile_url.absoluteString]];
  [arguments addObjectsFromArray:@[
    @"--headless",
    @"--nologo",
    @"--nodefault",
    @"--norestore",
    @"--convert-to",
    @"pdf",
    @"--outdir",
    work_dir_ns,
    pptx_path_ns,
  ]];

  if (!RunTask(soffice_ns, arguments, std_out, std_err, exit_code) || exit_code != 0) {
    out_error = BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  auto stem = fs::path(pptx_path).stem().string();
  auto generated_pdf = work_dir / (stem + ".pdf");
  if (!fs::exists(generated_pdf)) {
    out_error = "LibreOffice finished, but no PDF was generated.";
    return false;
  }

  auto final_pdf = fs::path(cache_dir) / "deck.pdf";
  fs::copy_file(generated_pdf, final_pdf, fs::copy_options::overwrite_existing);
  out_pdf_path = final_pdf.string();
  return true;
}

std::string PowerPointAppleScriptSaveAsSource()
{
  return R"APPLESCRIPT(
on wait_for_active_presentation(max_wait_seconds)
	repeat max_wait_seconds times
		tell application "Microsoft PowerPoint"
			try
				return active presentation
			end try
		end tell
		delay 1
	end repeat
	error "PowerPoint opened the file, but the presentation did not become active."
end wait_for_active_presentation

on wait_for_output(file_path, max_wait_seconds)
	repeat max_wait_seconds times
		try
			do shell script "/bin/test -f " & quoted form of file_path
			return true
		end try
		delay 1
	end repeat
	return false
end wait_for_output

on close_opened_presentation(opened_presentation)
	tell application "Microsoft PowerPoint"
		try
			close opened_presentation saving no
		end try
	end tell
end close_opened_presentation

on run argv
	if (count of argv) is not 2 then error "Expected input and output paths."
	set input_path to item 1 of argv
	set output_path to item 2 of argv

	try
		tell application "Microsoft PowerPoint"
			open POSIX file input_path
		end tell
		set opened_presentation to my wait_for_active_presentation(20)
		tell application "Microsoft PowerPoint"
			save active presentation in (POSIX file output_path) as save as PDF
		end tell
	on error err_message number err_number
		try
			my close_opened_presentation(opened_presentation)
		end try
		error "PowerPoint Save As export failed (" & err_number & "): " & err_message
	end try

	my close_opened_presentation(opened_presentation)

	if my wait_for_output(output_path, 20) is false then
		error "PowerPoint reported success but no PDF was created."
	end if

	return output_path
end run
)APPLESCRIPT";
}

bool RunAppleScriptFile(
  const std::string &cache_dir,
  const std::string &script_name,
  const std::string &script_source,
  const std::vector<std::string> &script_arguments,
  std::string &std_out,
  std::string &std_err,
  int &exit_code)
{
  auto script_path = fs::path(cache_dir) / script_name;
  std::string write_error;
  if (!WriteUtf8TextFile(ToNSString(script_path.string()), ToNSString(script_source), write_error)) {
    std_err = write_error;
    std_out.clear();
    exit_code = -1;
    return false;
  }

  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  [arguments addObject:ToNSString(script_path.string())];
  for (const auto &argument : script_arguments) {
    [arguments addObject:ToNSString(argument)];
  }

  return RunTask(@"/usr/bin/osascript", arguments, std_out, std_err, exit_code);
}

bool RunAppleScriptLines(
  const std::vector<std::string> &lines,
  std::string &std_out,
  std::string &std_err,
  int &exit_code)
{
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  for (const auto &line : lines) {
    [arguments addObject:@"-e"];
    [arguments addObject:ToNSString(line)];
  }

  return RunTask(@"/usr/bin/osascript", arguments, std_out, std_err, exit_code);
}

struct LivePowerPointSnapshot {
  std::string window_title;
  std::size_t current_index = 0;
  std::size_t slide_count = 0;
};

std::vector<std::string> SplitLines(const std::string &value)
{
  std::vector<std::string> lines;
  std::istringstream stream(value);
  std::string line;
  while (std::getline(stream, line)) {
    lines.push_back(TrimWhitespace(line));
  }
  return lines;
}

bool ParseLivePowerPointOutput(
  const std::string &std_out,
  LivePowerPointSnapshot &snapshot,
  std::string &out_error)
{
  const auto lines = SplitLines(std_out);
  if (lines.size() < 3 || lines[0].empty()) {
    out_error = "PowerPoint live mode returned an incomplete response.";
    return false;
  }

  try {
    const auto slide_number = std::stoul(lines[1]);
    const auto slide_count = std::stoul(lines[2]);
    snapshot.window_title = lines[0];
    snapshot.current_index = slide_number > 0 ? static_cast<std::size_t>(slide_number - 1) : 0;
    snapshot.slide_count = static_cast<std::size_t>(slide_count);
    return true;
  } catch (const std::exception &) {
    out_error = "PowerPoint live mode returned invalid slide information.";
    return false;
  }
}

std::string PowerPointAppleScriptLiveStartSource()
{
  return R"APPLESCRIPT(
on wait_for_slide_show_window(max_wait_seconds)
	repeat (max_wait_seconds * 10) times
		tell application "Microsoft PowerPoint"
			try
				set targetPresentation to active presentation
				set targetWindow to slide show window of targetPresentation
				set windowTitle to name of targetWindow
				set slideNumber to slide index of slide of slideshow view of targetWindow
				set slideCount to count of slides of targetPresentation
				return windowTitle & linefeed & (slideNumber as text) & linefeed & (slideCount as text)
			end try
		end tell
		delay 0.1
	end repeat
	error "PowerPoint live slideshow window did not appear."
end wait_for_slide_show_window

on run argv
	if (count of argv) is not 1 then error "Expected PowerPoint input path."
	set input_path to item 1 of argv

	tell application "Microsoft PowerPoint"
		activate
		open POSIX file input_path
		set targetPresentation to active presentation
		tell slide show settings of targetPresentation
			-- Windowed slide show keeps PowerPoint in a normal resizable
			-- window so the presenter can still use OBS (and the rest of the
			-- desktop) while the deck is running. OBS still captures the
			-- slide show window through the screen_capture source. Users who
			-- want full-screen kiosk can change `slide show type window` to
			-- `slide show type kiosk` here.
			set show type to slide show type window
			set show with presenter to false
			run slide show
		end tell
	end tell

	return my wait_for_slide_show_window(20)
end run
)APPLESCRIPT";
}

bool QueryPowerPointLiveState(LivePowerPointSnapshot &snapshot, std::string &out_error)
{
  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool ok = RunAppleScriptLines(
    {
      R"(tell application "Microsoft PowerPoint")",
      R"(set targetPresentation to active presentation)",
      R"(set targetWindow to slide show window of targetPresentation)",
      R"(set windowTitle to name of targetWindow)",
      R"(set slideNumber to slide index of slide of slideshow view of targetWindow)",
      R"(set slideCount to count of slides of targetPresentation)",
      R"(return windowTitle & linefeed & (slideNumber as text) & linefeed & (slideCount as text))",
      R"(end tell)",
    },
    std_out,
    std_err,
    exit_code);

  if (!ok || exit_code != 0) {
    out_error = "PowerPoint live query failed: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  return ParseLivePowerPointOutput(std_out, snapshot, out_error);
}

bool StartPowerPointLiveSession(
  const std::string &pptx_path,
  const std::string &cache_dir,
  LivePowerPointSnapshot &snapshot,
  std::string &out_error)
{
  const auto powerpoint_bundle = FindPowerPointBundle();
  if (powerpoint_bundle.empty()) {
    out_error = "Microsoft PowerPoint was not found.";
    return false;
  }

  // Fast path: if PowerPoint already has a slideshow running (e.g. OBS was
  // restarted while PowerPoint stayed open from a prior session), just
  // reattach to that existing session instead of restaging the file and
  // re-launching the show. QueryPowerPointLiveState queries PowerPoint's
  // active presentation; if it comes back with a valid window title, we're
  // good to go.
  {
    std::string query_error;
    LivePowerPointSnapshot existing;
    if (QueryPowerPointLiveState(existing, query_error) && !existing.window_title.empty()) {
      snapshot = existing;
      return true;
    }
  }

  auto work_dir = fs::path(cache_dir) / "powerpoint-live";
  std::error_code error;
  fs::create_directories(work_dir, error);
  if (error) {
    out_error = "Could not prepare PowerPoint live cache folder.";
    return false;
  }

  const auto copied_input = work_dir / fs::path(pptx_path).filename();
  error.clear();
  fs::copy_file(pptx_path, copied_input, fs::copy_options::overwrite_existing, error);
  if (error) {
    // Copy may fail if PowerPoint still has the destination open from a
    // previous run (leaves a ~$...pptx lock file next to it). If we still
    // have a usable copy from an earlier session, reuse it; otherwise try
    // a tmp-dir rename, and only then report an error.
    std::error_code exists_error;
    if (!fs::exists(copied_input, exists_error)) {
      auto tmp_staged = work_dir / ("pptbridge_stage_" + fs::path(pptx_path).filename().string());
      error.clear();
      fs::copy_file(pptx_path, tmp_staged, fs::copy_options::overwrite_existing, error);
      if (error) {
        out_error = "Could not stage PowerPoint file for live mode.";
        return false;
      }
    }
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool launched = RunAppleScriptFile(
    cache_dir,
    "pptbridge_powerpoint_live_start.applescript",
    PowerPointAppleScriptLiveStartSource(),
    { copied_input.string() },
    std_out,
    std_err,
    exit_code);

  if (!launched || exit_code != 0) {
    out_error = "PowerPoint live mode failed to start: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  return ParseLivePowerPointOutput(std_out, snapshot, out_error);
}

bool RunPowerPointLiveCommand(
  const std::string &command_line,
  LivePowerPointSnapshot &snapshot,
  std::string &out_error)
{
  std::vector<std::string> lines = {
    R"(tell application "Microsoft PowerPoint")",
    R"(set targetPresentation to active presentation)",
  };
  if (!command_line.empty()) {
    lines.push_back(command_line);
    lines.push_back(R"(delay 0.05)");
  }
  lines.push_back(R"(set targetWindow to slide show window of targetPresentation)");
  lines.push_back(R"(set windowTitle to name of targetWindow)");
  lines.push_back(R"(set slideNumber to slide index of slide of slideshow view of targetWindow)");
  lines.push_back(R"(set slideCount to count of slides of targetPresentation)");
  lines.push_back(R"(return windowTitle & linefeed & (slideNumber as text) & linefeed & (slideCount as text))");
  lines.push_back(R"(end tell)");

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool ok = RunAppleScriptLines(lines, std_out, std_err, exit_code);
  if (!ok || exit_code != 0) {
    out_error = "PowerPoint live command failed: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  return ParseLivePowerPointOutput(std_out, snapshot, out_error);
}

bool ConvertPptxToPdfWithPowerPoint(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::string &out_pdf_path,
  std::string &out_error)
{
  const auto powerpoint_bundle = FindPowerPointBundle();
  if (powerpoint_bundle.empty()) {
    out_error = "Microsoft PowerPoint was not found.";
    return false;
  }

  auto work_dir = fs::path(cache_dir) / "powerpoint";
  std::error_code error;
  fs::create_directories(work_dir, error);
  if (error) {
    out_error = "Could not prepare PowerPoint cache folder.";
    return false;
  }

  const auto copied_input = work_dir / fs::path(pptx_path).filename();
  error.clear();
  fs::copy_file(pptx_path, copied_input, fs::copy_options::overwrite_existing, error);
  if (error) {
    out_error = "Could not stage PowerPoint file for export.";
    return false;
  }

  auto output_pdf = fs::path(cache_dir) / "deck.pdf";
  std::error_code remove_error;
  fs::remove(output_pdf, remove_error);

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool launched = RunAppleScriptFile(
    cache_dir,
    "pptbridge_powerpoint_save_as.applescript",
    PowerPointAppleScriptSaveAsSource(),
    { copied_input.string(), output_pdf.string() },
    std_out,
    std_err,
    exit_code);

  if (launched && exit_code == 0 && fs::exists(output_pdf)) {
    out_pdf_path = output_pdf.string();
    blog(LOG_INFO, "[PPTBridge] PowerPoint fallback exported '%s'", pptx_path.c_str());
    return true;
  }

  out_error = "PowerPoint Save As PDF failed: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
  return false;
}

bool ConvertPptxToPdf(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::string &out_pdf_path,
  std::string &out_error)
{
  if (pptx_path.empty()) {
    out_error = "Choose a .pptx file in source properties.";
    return false;
  }
  if (!fs::exists(pptx_path)) {
    out_error = "The selected .pptx file could not be found.";
    return false;
  }

  if (TryUseCachedPdf(pptx_path, cache_dir, out_pdf_path)) {
    blog(LOG_INFO, "[PPTBridge] Using cached PDF for '%s'", pptx_path.c_str());
    return true;
  }

  if (TryUseLegacyCachedPdf(pptx_path, cache_dir, out_pdf_path)) {
    blog(LOG_INFO, "[PPTBridge] Reused legacy cached PDF for '%s'", pptx_path.c_str());
    return true;
  }

  std::string powerpoint_error;
  if (!FindPowerPointBundle().empty()) {
    if (ConvertPptxToPdfWithPowerPoint(pptx_path, cache_dir, out_pdf_path, powerpoint_error)) {
      return true;
    }

    blog(
      LOG_WARNING,
      "[PPTBridge] PowerPoint export failed for '%s'; trying LibreOffice fallback: %s",
      pptx_path.c_str(),
      powerpoint_error.c_str());
  }

  std::string libreoffice_error;
  if (ConvertPptxToPdfWithLibreOffice(pptx_path, cache_dir, out_pdf_path, libreoffice_error)) {
    return true;
  }

  out_error = "PowerPoint export failed: " + (powerpoint_error.empty() ? std::string("PowerPoint was not found.") : powerpoint_error);
  if (!libreoffice_error.empty()) {
    out_error += " LibreOffice fallback failed: " + libreoffice_error;
  }
  return false;
}

std::vector<std::string> ListSlideEntries(const std::string &pptx_path)
{
  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  if (!RunTask(
        @"/usr/bin/unzip",
        @[ @"-Z1", ToNSString(pptx_path) ],
        std_out,
        std_err,
        exit_code) ||
      exit_code != 0) {
    return {};
  }

  std::vector<std::pair<int, std::string>> numbered;
  NSArray<NSString *> *lines =
    [ToNSString(std_out) componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    if (![line hasPrefix:@"ppt/slides/slide"] || ![line hasSuffix:@".xml"]) {
      continue;
    }
    if ([line containsString:@"/_rels/"]) {
      continue;
    }

    NSString *last = line.lastPathComponent.stringByDeletingPathExtension;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSMutableString *numeric = [NSMutableString string];
    for (NSUInteger i = 0; i < last.length; ++i) {
      unichar c = [last characterAtIndex:i];
      if ([digits characterIsMember:c]) {
        [numeric appendFormat:@"%C", c];
      }
    }
    int index = numeric.intValue;
    if (index > 0) {
      numbered.emplace_back(index, ToStdString(line));
    }
  }

  std::sort(numbered.begin(), numbered.end(), [](const auto &a, const auto &b) {
    return a.first < b.first;
  });

  std::vector<std::string> ordered;
  for (const auto &entry : numbered) {
    ordered.push_back(entry.second);
  }
  return ordered;
}

NSString *ReadZipEntry(const std::string &pptx_path, const std::string &entry_path)
{
  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  RunTask(
    @"/usr/bin/unzip",
    @[ @"-p", ToNSString(pptx_path), ToNSString(entry_path) ],
    std_out,
    std_err,
    exit_code);
  if (exit_code != 0) {
    return nil;
  }
  return ToNSString(std_out);
}

NSArray<NSXMLNode *> *XPath(NSXMLNode *node, NSString *query)
{
  NSError *error = nil;
  NSArray<NSXMLNode *> *result = [node nodesForXPath:query error:&error];
  return error ? @[] : result;
}

std::string JoinTextFromNodes(NSArray<NSXMLNode *> *nodes, NSString *separator)
{
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (NSXMLNode *node in nodes) {
    NSString *value = [node stringValue];
    if (value.length > 0) {
      [parts addObject:value];
    }
  }
  return ToStdString([parts componentsJoinedByString:separator]);
}

SlideMetadata ExtractMetadataForSlide(
  const std::string &pptx_path,
  const std::string &slide_entry,
  const std::string &notes_entry)
{
  SlideMetadata meta;

  NSString *slide_xml = ReadZipEntry(pptx_path, slide_entry);
  if (slide_xml.length > 0) {
    NSError *error = nil;
    NSXMLDocument *document =
      [[NSXMLDocument alloc] initWithXMLString:slide_xml options:0 error:&error];
    if (!error) {
      NSArray<NSXMLNode *> *shapes = XPath(document, @"//*[local-name()='sp']");
      for (NSXMLNode *shape in shapes) {
        NSArray<NSXMLNode *> *placeholders =
          XPath(shape, @"./*[local-name()='nvSpPr']/*[local-name()='nvPr']/*[local-name()='ph']");
        for (NSXMLNode *placeholder_node in placeholders) {
          if (![placeholder_node isKindOfClass:[NSXMLElement class]]) {
            continue;
          }
          NSString *type = [(NSXMLElement *)placeholder_node attributeForName:@"type"].stringValue ?: @"";
          if ([type isEqualToString:@"title"] || [type isEqualToString:@"ctrTitle"]) {
            meta.title = JoinTextFromNodes(XPath(shape, @".//*[local-name()='t']/text()"), @" ");
            break;
          }
        }
        if (!meta.title.empty()) {
          break;
        }
      }
    }
  }

  NSString *notes_xml = ReadZipEntry(pptx_path, notes_entry);
  if (notes_xml.length > 0) {
    NSError *error = nil;
    NSXMLDocument *document =
      [[NSXMLDocument alloc] initWithXMLString:notes_xml options:0 error:&error];
    if (!error) {
      NSMutableArray<NSString *> *lines = [NSMutableArray array];
      NSArray<NSXMLNode *> *shapes = XPath(document, @"//*[local-name()='sp']");
      for (NSXMLNode *shape in shapes) {
        NSArray<NSXMLNode *> *placeholders =
          XPath(shape, @"./*[local-name()='nvSpPr']/*[local-name()='nvPr']/*[local-name()='ph']");
        bool include_shape = placeholders.count == 0;
        for (NSXMLNode *placeholder_node in placeholders) {
          if (![placeholder_node isKindOfClass:[NSXMLElement class]]) {
            continue;
          }
          NSString *type = [(NSXMLElement *)placeholder_node attributeForName:@"type"].stringValue ?: @"";
          if ([type isEqualToString:@"body"] || [type isEqualToString:@"subTitle"]) {
            include_shape = true;
            break;
          }
          if ([type isEqualToString:@"hdr"] ||
              [type isEqualToString:@"dt"] ||
              [type isEqualToString:@"ftr"] ||
              [type isEqualToString:@"sldNum"] ||
              [type isEqualToString:@"img"]) {
            include_shape = false;
          }
        }
        if (!include_shape) {
          continue;
        }

        NSArray<NSXMLNode *> *paragraphs = XPath(shape, @".//*[local-name()='p']");
        for (NSXMLNode *paragraph in paragraphs) {
          NSString *line = ToNSString(JoinTextFromNodes(XPath(paragraph, @".//*[local-name()='t']/text()"), @""));
          NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if (trimmed.length > 0) {
            [lines addObject:trimmed];
          }
        }
      }

      if (lines.count == 0) {
        NSArray<NSXMLNode *> *paragraphs = XPath(document, @"//*[local-name()='p']");
        for (NSXMLNode *paragraph in paragraphs) {
          NSString *line = ToNSString(JoinTextFromNodes(XPath(paragraph, @".//*[local-name()='t']/text()"), @""));
          NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if (trimmed.length > 0) {
            [lines addObject:trimmed];
          }
        }
      }

      meta.notes = ToStdString(JoinLines(lines));
    }
  }

  return meta;
}

std::string ResolveNotesEntryForSlide(const std::string &pptx_path, const std::string &slide_entry)
{
  const auto slide_path = fs::path(slide_entry);
  const auto rels_entry =
    (slide_path.parent_path() / "_rels" / (slide_path.filename().string() + ".rels")).generic_string();
  const auto relationships = ParseRelationships(pptx_path, rels_entry);
  for (const auto &[identifier, info] : relationships) {
    UNUSED_PARAMETER(identifier);
    if (info.external) {
      continue;
    }
    if (StringContainsCaseInsensitive(info.type, "/notesSlide")) {
      return ResolveZipTarget(slide_entry, info.target);
    }
  }

  return {};
}

std::vector<SlideMetadata> ExtractDeckMetadata(const std::string &pptx_path, std::size_t slide_count)
{
  std::vector<SlideMetadata> result(slide_count);
  auto slide_entries = ListSlideEntries(pptx_path);
  for (std::size_t index = 0; index < slide_entries.size() && index < slide_count; ++index) {
    auto notes_entry = ResolveNotesEntryForSlide(pptx_path, slide_entries[index]);
    result[index] = ExtractMetadataForSlide(pptx_path, slide_entries[index], notes_entry);
  }
  return result;
}

struct SlideCanvasSize {
  double width = 9144000.0;
  double height = 6858000.0;
};

SlideCanvasSize ExtractSlideCanvasSize(const std::string &pptx_path)
{
  SlideCanvasSize size;
  NSString *presentation_xml = ReadZipEntry(pptx_path, "ppt/presentation.xml");
  if (presentation_xml.length == 0) {
    return size;
  }

  NSError *error = nil;
  NSXMLDocument *document =
    [[NSXMLDocument alloc] initWithXMLString:presentation_xml options:0 error:&error];
  if (error) {
    return size;
  }

  NSArray<NSXMLNode *> *nodes = XPath(document, @"//*[local-name()='sldSz']");
  if (nodes.count == 0) {
    return size;
  }

  NSString *cx = AttributeByLocalName(nodes.firstObject, @"cx");
  NSString *cy = AttributeByLocalName(nodes.firstObject, @"cy");
  if (cx.length > 0) {
    size.width = std::max(1.0, cx.doubleValue);
  }
  if (cy.length > 0) {
    size.height = std::max(1.0, cy.doubleValue);
  }
  return size;
}

bool ExtractNormalizedRect(NSXMLNode *shape, const SlideCanvasSize &slide_size, double &x, double &y, double &width, double &height)
{
  NSArray<NSXMLNode *> *xfrms =
    XPath(shape, @"./*[local-name()='spPr']/*[local-name()='xfrm'] | ./*[local-name()='xfrm']");
  if (xfrms.count == 0) {
    return false;
  }

  NSXMLNode *xfrm = xfrms.firstObject;
  NSArray<NSXMLNode *> *offs = XPath(xfrm, @"./*[local-name()='off']");
  NSArray<NSXMLNode *> *exts = XPath(xfrm, @"./*[local-name()='ext']");
  if (offs.count == 0 || exts.count == 0) {
    return false;
  }

  NSString *off_x = AttributeByLocalName(offs.firstObject, @"x");
  NSString *off_y = AttributeByLocalName(offs.firstObject, @"y");
  NSString *ext_cx = AttributeByLocalName(exts.firstObject, @"cx");
  NSString *ext_cy = AttributeByLocalName(exts.firstObject, @"cy");
  if (off_x.length == 0 || off_y.length == 0 || ext_cx.length == 0 || ext_cy.length == 0) {
    return false;
  }

  x = std::clamp(off_x.doubleValue / slide_size.width, 0.0, 1.0);
  y = std::clamp(off_y.doubleValue / slide_size.height, 0.0, 1.0);
  width = std::clamp(ext_cx.doubleValue / slide_size.width, 0.0, 1.0);
  height = std::clamp(ext_cy.doubleValue / slide_size.height, 0.0, 1.0);
  return width > 0.0 && height > 0.0;
}

std::string BuildMediaSignatureKey(const EmbeddedMedia &media)
{
  std::ostringstream stream;
  stream << static_cast<int>(media.kind) << "|" << media.file_path << "|"
         << media.x << "|" << media.y << "|" << media.width << "|" << media.height;
  return stream.str();
}

std::vector<std::string> CandidateRelationshipIds(NSXMLNode *shape)
{
  std::vector<std::string> ids;
  NSArray<NSXMLNode *> *nodes = XPath(shape, @".//*");
  for (NSXMLNode *node in nodes) {
    if (![node isKindOfClass:[NSXMLElement class]]) {
      continue;
    }

    for (NSString *attribute_name in @[ @"embed", @"link", @"id" ]) {
      NSString *value = AttributeByLocalName(node, attribute_name);
      if (value.length > 0 && [value hasPrefix:@"rId"]) {
        ids.push_back(ToStdString(value));
      }
    }
  }

  std::sort(ids.begin(), ids.end());
  ids.erase(std::unique(ids.begin(), ids.end()), ids.end());
  return ids;
}

bool LooksLikeMediaRelationship(const RelationshipInfo &relationship, const std::string &resolved_target)
{
  if (relationship.external) {
    return false;
  }

  const auto extension = ToLowerCopy(fs::path(resolved_target).extension().string());
  if (IsImageExtension(extension)) {
    return false;
  }
  if (IsVideoExtension(extension) || IsAudioExtension(extension)) {
    return true;
  }

  return StringContainsCaseInsensitive(relationship.type, "media") ||
         StringContainsCaseInsensitive(relationship.type, "video") ||
         StringContainsCaseInsensitive(relationship.type, "audio");
}

EmbeddedMediaKind DetectMediaKind(const RelationshipInfo &relationship, const std::string &resolved_target)
{
  const auto extension = ToLowerCopy(fs::path(resolved_target).extension().string());
  if (IsAudioExtension(extension) || StringContainsCaseInsensitive(relationship.type, "audio")) {
    return EmbeddedMediaKind::Audio;
  }
  return EmbeddedMediaKind::Video;
}

std::vector<EmbeddedMedia> ExtractSlideMedia(
  const std::string &pptx_path,
  const std::string &slide_entry,
  const std::string &cache_dir,
  const SlideCanvasSize &slide_size,
  std::unordered_map<std::string, std::string> &extracted_cache)
{
  std::vector<EmbeddedMedia> result;

  NSString *slide_xml = ReadZipEntry(pptx_path, slide_entry);
  if (slide_xml.length == 0) {
    return result;
  }

  auto rels_entry = fs::path(slide_entry).parent_path() / "_rels" / (fs::path(slide_entry).filename().string() + ".rels");
  auto relationships = ParseRelationships(pptx_path, rels_entry.generic_string());
  if (relationships.empty()) {
    return result;
  }

  NSError *error = nil;
  NSXMLDocument *document =
    [[NSXMLDocument alloc] initWithXMLString:slide_xml options:0 error:&error];
  if (error) {
    return result;
  }

  NSArray<NSXMLNode *> *shapes = XPath(document, @"/*[local-name()='sld']/*[local-name()='cSld']/*[local-name()='spTree']/*");
  std::unordered_map<std::string, bool> dedupe;
  for (NSXMLNode *shape in shapes) {
    auto ids = CandidateRelationshipIds(shape);
    if (ids.empty()) {
      continue;
    }

    std::string chosen_resolved_target;
    RelationshipInfo chosen_relationship;
    bool found = false;
    int best_score = -1;
    for (const auto &identifier : ids) {
      auto it = relationships.find(identifier);
      if (it == relationships.end()) {
        continue;
      }

      const auto resolved_target = ResolveZipTarget(slide_entry, it->second.target);
      if (!LooksLikeMediaRelationship(it->second, resolved_target)) {
        continue;
      }

      int score = 10;
      if (StringContainsCaseInsensitive(it->second.type, "video") ||
          StringContainsCaseInsensitive(it->second.type, "audio")) {
        score += 20;
      }

      const auto extension = ToLowerCopy(fs::path(resolved_target).extension().string());
      if (IsVideoExtension(extension) || IsAudioExtension(extension)) {
        score += 10;
      }

      if (score > best_score) {
        best_score = score;
        chosen_relationship = it->second;
        chosen_resolved_target = resolved_target;
        found = true;
      }
    }

    if (!found || chosen_resolved_target.empty()) {
      continue;
    }

    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;
    ExtractNormalizedRect(shape, slide_size, x, y, width, height);

    std::string extracted_path;
    auto extracted_it = extracted_cache.find(chosen_resolved_target);
    if (extracted_it != extracted_cache.end()) {
      extracted_path = extracted_it->second;
    } else {
      std::string extraction_error;
      if (!ExtractZipEntryToFile(
            pptx_path,
            chosen_resolved_target,
            (fs::path(cache_dir) / "embedded-media").string(),
            extracted_path,
            extraction_error)) {
        blog(
          LOG_WARNING,
          "[PPTBridge] Failed to extract media '%s' from '%s': %s",
          chosen_resolved_target.c_str(),
          pptx_path.c_str(),
          extraction_error.c_str());
        continue;
      }
      extracted_cache[chosen_resolved_target] = extracted_path;
    }

    EmbeddedMedia media;
    media.kind = DetectMediaKind(chosen_relationship, chosen_resolved_target);
    media.file_path = extracted_path;
    media.original_entry = chosen_resolved_target;
    media.x = x;
    media.y = y;
    media.width = width;
    media.height = height;

    const auto signature = BuildMediaSignatureKey(media);
    if (dedupe.emplace(signature, true).second) {
      result.push_back(std::move(media));
    }
  }

  return result;
}

std::vector<std::vector<EmbeddedMedia>> ExtractDeckMedia(
  const std::string &pptx_path,
  const std::string &cache_dir,
  std::size_t slide_count)
{
  std::vector<std::vector<EmbeddedMedia>> media_by_slide(slide_count);
  auto slide_entries = ListSlideEntries(pptx_path);
  auto slide_size = ExtractSlideCanvasSize(pptx_path);
  auto media_cache_dir = fs::path(cache_dir) / "embedded-media";
  fs::create_directories(media_cache_dir);

  std::unordered_map<std::string, std::string> extracted_cache;
  for (std::size_t index = 0; index < slide_entries.size() && index < slide_count; ++index) {
    media_by_slide[index] = ExtractSlideMedia(
      pptx_path,
      slide_entries[index],
      cache_dir,
      slide_size,
      extracted_cache);
  }

  return media_by_slide;
}

NSBitmapImageRep *CreateBitmap(uint32_t width, uint32_t height)
{
  return [[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes:nullptr
                  pixelsWide:static_cast<NSInteger>(width)
                  pixelsHigh:static_cast<NSInteger>(height)
               bitsPerSample:8
             samplesPerPixel:4
                    hasAlpha:YES
                    isPlanar:NO
              colorSpaceName:NSDeviceRGBColorSpace
                 bitmapFormat:NSBitmapFormatAlphaFirst | NSBitmapFormatThirtyTwoBitLittleEndian
                  bytesPerRow:static_cast<NSInteger>(width * 4)
                 bitsPerPixel:32];
}

// Copies the drawn bitmap into `out_pixels` in GS_BGRA byte order (B,G,R,A).
// Empirically, the NSBitmapImageRep produced by CreateBitmap stores bytes in
// A,R,G,B order on macOS despite the AlphaFirst|LittleEndian flags, which
// caused OBS to display the presenter thumbnail with the R/B channels
// scrambled (teal shapes appearing as purple/lavender). This helper performs
// the byte re-order so the on-screen colors match the real PowerPoint slide.
void CopyBitmapToBGRA(NSBitmapImageRep *bitmap, uint32_t height, std::vector<uint8_t> &out_pixels)
{
  const uint32_t stride = static_cast<uint32_t>(bitmap.bytesPerRow);
  const uint8_t *src = bitmap.bitmapData;
  out_pixels.resize(static_cast<size_t>(stride) * height);
  uint8_t *dst = out_pixels.data();
  const size_t total = static_cast<size_t>(stride) * height;
  for (size_t i = 0; i + 3 < total; i += 4) {
    const uint8_t a = src[i + 0];
    const uint8_t r = src[i + 1];
    const uint8_t g = src[i + 2];
    const uint8_t b = src[i + 3];
    dst[i + 0] = b;
    dst[i + 1] = g;
    dst[i + 2] = r;
    dst[i + 3] = a;
  }
}

NSRect AspectFitRect(NSSize content_size, NSRect bounds)
{
  if (content_size.width <= 0 || content_size.height <= 0) {
    return bounds;
  }

  CGFloat scale = std::min(bounds.size.width / content_size.width, bounds.size.height / content_size.height);
  NSSize fitted = NSMakeSize(content_size.width * scale, content_size.height * scale);
  return NSMakeRect(
    bounds.origin.x + (bounds.size.width - fitted.width) * 0.5,
    bounds.origin.y + (bounds.size.height - fitted.height) * 0.5,
    fitted.width,
    fitted.height);
}

void FillRect(NSRect rect, NSColor *color)
{
  [color setFill];
  NSRectFill(rect);
}

void DrawLabel(NSString *text, NSRect rect, NSColor *color, NSFont *font)
{
  NSDictionary *attrs = @{
    NSForegroundColorAttributeName : color,
    NSFontAttributeName : font,
  };
  [text drawInRect:rect withAttributes:attrs];
}

void DrawCenteredMessage(NSString *title, NSString *subtitle, NSRect bounds)
{
  NSDictionary *title_attrs = @{
    NSForegroundColorAttributeName : [NSColor colorWithWhite:0.96 alpha:1.0],
    NSFontAttributeName : [NSFont boldSystemFontOfSize:28],
  };
  NSDictionary *subtitle_attrs = @{
    NSForegroundColorAttributeName : [NSColor colorWithWhite:0.62 alpha:1.0],
    NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
  };

  NSSize title_size = [title sizeWithAttributes:title_attrs];
  NSSize subtitle_size = [subtitle sizeWithAttributes:subtitle_attrs];
  CGFloat center_x = bounds.origin.x + bounds.size.width * 0.5;
  CGFloat center_y = bounds.origin.y + bounds.size.height * 0.5;

  [title drawAtPoint:NSMakePoint(center_x - title_size.width * 0.5, center_y + 10) withAttributes:title_attrs];
  [subtitle drawAtPoint:NSMakePoint(center_x - subtitle_size.width * 0.5, center_y - 24) withAttributes:subtitle_attrs];
}

void DrawPageThumbnail(PDFDocument *document, std::size_t index, NSRect rect)
{
  if (!document || index >= static_cast<std::size_t>(document.pageCount)) {
    return;
  }
  PDFPage *page = [document pageAtIndex:static_cast<NSInteger>(index)];
  if (!page) {
    return;
  }
  NSImage *thumbnail = [page thumbnailOfSize:rect.size forBox:kPDFDisplayBoxMediaBox];
  if (!thumbnail) {
    return;
  }
  NSRect destination = AspectFitRect(thumbnail.size, rect);
  [thumbnail drawInRect:destination];
}

std::string FormatTimer(uint64_t seconds)
{
  auto minutes = seconds / 60;
  auto remaining = seconds % 60;
  char buffer[16];
  snprintf(buffer, sizeof(buffer), "%02llu:%02llu",
    static_cast<unsigned long long>(minutes),
    static_cast<unsigned long long>(remaining));
  return buffer;
}

}  // namespace

struct PresentationDocument::Impl {
  explicit Impl(std::string input_path)
    : path(std::move(input_path)),
      name(fs::path(path).filename().string())
  {
  }

  mutable std::mutex mutex;
  std::string path;
  std::string name;
  std::string cache_dir;
  std::string pdf_path;
  std::string error;
  std::vector<SlideMetadata> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  bool loading = false;
  bool loaded = false;
  bool load_requested = true;
  bool presenter_assets_wanted = false;
  bool live_powerpoint_enabled = false;
  bool live_ready = false;
  bool live_sync_in_flight = false;
  bool black = false;
  bool current_media_triggered = false;
  std::size_t current = 0;
  std::size_t live_slide_count = 0;
  std::string live_window_title;
  std::string live_error;
  Clock::time_point live_last_sync = Clock::time_point::min();
  uint64_t version = 1;
  Clock::time_point started_at = Clock::now();
  PDFDocument *__strong pdf_document = nil;
};

PresentationDocument::PresentationDocument(std::string pptx_path)
  : impl_(std::make_unique<Impl>(std::move(pptx_path)))
{
}

PresentationDocument::~PresentationDocument() = default;

const std::string &PresentationDocument::Path() const
{
  return impl_->path;
}

std::string PresentationDocument::Name() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->name;
}

void PresentationDocument::SetLivePowerPointEnabled(bool enabled)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  // Live PowerPoint mode is a PowerPoint-only feature. For raw .pdf decks
  // we force the flag off so the source always takes the PDFKit path.
  const auto extension_lower = ToLowerCopy(fs::path(impl_->path).extension().string());
  if (extension_lower == ".pdf") {
    enabled = false;
  }
  if (impl_->live_powerpoint_enabled == enabled) {
    return;
  }

  impl_->live_powerpoint_enabled = enabled;
  impl_->live_error.clear();
  if (!enabled) {
    impl_->live_ready = false;
    impl_->live_window_title.clear();
    impl_->live_slide_count = 0;
    impl_->live_sync_in_flight = false;
  }
  impl_->load_requested = true;
  impl_->version += 1;
}

bool PresentationDocument::IsLivePowerPointEnabled() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_powerpoint_enabled;
}

bool PresentationDocument::IsLivePowerPointReady() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_powerpoint_enabled && impl_->live_ready;
}

std::string PresentationDocument::LiveWindowTitle() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_window_title;
}

void PresentationDocument::SetPresenterAssetsWanted(bool wanted)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!wanted) {
    return;
  }

  if (impl_->presenter_assets_wanted) {
    return;
  }

  impl_->presenter_assets_wanted = true;
  if (!impl_->loaded) {
    impl_->load_requested = true;
  }
  impl_->version += 1;
}

void PresentationDocument::EnsureLoadingAsync()
{
  StartLoadIfNeeded(false);
}

void PresentationDocument::ReloadAsync()
{
  StartLoadIfNeeded(true);
}

void PresentationDocument::SyncLiveStateAsync()
{
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->live_powerpoint_enabled || !impl_->live_ready || impl_->live_sync_in_flight) {
      return;
    }

    const auto now = Clock::now();
    if (impl_->live_last_sync != Clock::time_point::min() &&
        now - impl_->live_last_sync < std::chrono::milliseconds(180)) {
      return;
    }

    impl_->live_sync_in_flight = true;
  }

  auto self = shared_from_this();
  std::thread([self]() {
    LivePowerPointSnapshot snapshot;
    std::string error;
    const bool ok = QueryPowerPointLiveState(snapshot, error);

    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    self->impl_->live_sync_in_flight = false;
    self->impl_->live_last_sync = Clock::now();
    if (!self->impl_->live_powerpoint_enabled) {
      return;
    }

    if (!ok) {
      self->impl_->live_error = error;
      return;
    }

    const bool changed =
      self->impl_->current != snapshot.current_index ||
      self->impl_->live_slide_count != snapshot.slide_count ||
      self->impl_->live_window_title != snapshot.window_title ||
      !self->impl_->live_ready;

    self->impl_->live_ready = true;
    self->impl_->live_error.clear();
    self->impl_->live_window_title = snapshot.window_title;
    self->impl_->live_slide_count = snapshot.slide_count;
    self->impl_->current = snapshot.current_index;
    if (changed) {
      self->impl_->version += 1;
    }
  }).detach();
}

void PresentationDocument::StartLoadIfNeeded(bool force_reload)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->loading) {
    return;
  }
  if (!force_reload && !impl_->load_requested) {
    return;
  }

  impl_->loading = true;
  impl_->load_requested = false;
  if (force_reload) {
    impl_->loaded = false;
  }
  impl_->error.clear();
  impl_->version += 1;

  auto self = shared_from_this();
  std::thread([self]() { self->LoadOnWorker(); }).detach();
}

void PresentationDocument::LoadOnWorker()
{
  @autoreleasepool {
    std::string pdf_path;
    std::string error;
    auto cache_dir = CacheDirectoryForDeck(impl_->path);

    // Native PDF path: if the user points a source directly at a .pdf file
    // (i.e. someone brought a PDF presentation, no PowerPoint involved) we
    // skip PowerPoint/LibreOffice conversion and the live slideshow session
    // entirely. PDFKit drives the rendering and Next/Previous/First/Last/
    // Black all operate on the PDF pages directly via the same codepath used
    // for converted PPTX decks.
    const auto extension_lower = ToLowerCopy(fs::path(impl_->path).extension().string());
    const bool is_pdf_source = (extension_lower == ".pdf");
    if (is_pdf_source) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      if (impl_->live_powerpoint_enabled) {
        impl_->live_powerpoint_enabled = false;
        impl_->live_ready = false;
        impl_->live_window_title.clear();
        impl_->live_slide_count = 0;
        impl_->live_sync_in_flight = false;
      }
    }

    bool live_enabled = false;
    bool presenter_assets_wanted = false;
    bool already_live_ready = false;
    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      live_enabled = impl_->live_powerpoint_enabled;
      presenter_assets_wanted = impl_->presenter_assets_wanted;
      already_live_ready = impl_->live_ready;
    }

    if (live_enabled && !already_live_ready) {
      LivePowerPointSnapshot live_snapshot;
      std::string live_error;
      if (StartPowerPointLiveSession(impl_->path, cache_dir, live_snapshot, live_error)) {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->cache_dir = cache_dir;
        impl_->live_ready = true;
        impl_->live_error.clear();
        impl_->live_window_title = live_snapshot.window_title;
        impl_->live_slide_count = live_snapshot.slide_count;
        impl_->current = live_snapshot.current_index;
        impl_->black = false;
        impl_->current_media_triggered = false;
        impl_->started_at = Clock::now();
        impl_->version += 1;
        blog(LOG_INFO,
          "[PPTBridge] PowerPoint live mode started for '%s' (%s)",
          impl_->path.c_str(),
          live_snapshot.window_title.c_str());
      } else {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->live_ready = false;
        impl_->live_error = live_error;
        impl_->live_window_title.clear();
        impl_->live_slide_count = 0;
        impl_->version += 1;
        blog(LOG_WARNING, "[PPTBridge] Live mode failed for '%s': %s", impl_->path.c_str(), live_error.c_str());
      }
    }

    if (live_enabled && !presenter_assets_wanted) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->cache_dir = cache_dir;
      impl_->loading = false;
      impl_->loaded = false;
      impl_->error.clear();
      impl_->version += 1;
      return;
    }

    if (is_pdf_source) {
      // Native PDF path — treat the user-supplied file as the deck directly.
      if (!fs::exists(impl_->path)) {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->loading = false;
        impl_->loaded = false;
        impl_->error = "The selected .pdf file could not be found.";
        impl_->version += 1;
        return;
      }
      std::error_code cache_error;
      fs::create_directories(cache_dir, cache_error);
      pdf_path = impl_->path;
    } else if (!ConvertPptxToPdf(impl_->path, cache_dir, pdf_path, error)) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->loading = false;
      impl_->loaded = false;
      impl_->error = error;
      impl_->version += 1;
      blog(LOG_WARNING, "[PPTBridge] Failed to load '%s': %s", impl_->path.c_str(), error.c_str());
      return;
    }

    PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:ToNSString(pdf_path)]];
    if (!document || document.pageCount <= 0) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->loading = false;
      impl_->loaded = false;
      impl_->error = "The generated PDF could not be opened by PDFKit.";
      impl_->version += 1;
      blog(LOG_WARNING, "[PPTBridge] PDFKit could not open generated PDF for '%s'", impl_->path.c_str());
      return;
    }

    auto slide_count = static_cast<std::size_t>(document.pageCount);
    // pptx-only metadata extractors read inside the .pptx zip; skip them
    // entirely when the source is a standalone .pdf so we don't spawn
    // unzip processes against a file that is not a zip archive.
    std::vector<SlideMetadata> metadata;
    std::vector<std::vector<EmbeddedMedia>> media_by_slide;
    if (!is_pdf_source) {
      metadata = ExtractDeckMetadata(impl_->path, slide_count);
      media_by_slide = ExtractDeckMedia(impl_->path, cache_dir, slide_count);
    } else {
      metadata.resize(slide_count);
      media_by_slide.resize(slide_count);
      for (std::size_t index = 0; index < slide_count; ++index) {
        metadata[index].title = "Page " + std::to_string(index + 1);
      }
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->cache_dir = cache_dir;
    impl_->pdf_path = pdf_path;
    impl_->slides = std::move(metadata);
    impl_->media_by_slide = std::move(media_by_slide);
    impl_->pdf_document = document;
    impl_->loaded = true;
    impl_->loading = false;
    impl_->current_media_triggered = false;
    if (!impl_->live_ready) {
      impl_->black = false;
      impl_->current = 0;
      impl_->started_at = Clock::now();
    }
    impl_->error.clear();
    impl_->version += 1;
    blog(LOG_INFO,
      "[PPTBridge] Loaded '%s' with %ld slide(s)",
      impl_->path.c_str(),
      static_cast<long>(document.pageCount));
  }
}

bool PresentationDocument::IsLoaded() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->loaded;
}

bool PresentationDocument::IsLoading() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->loading;
}

std::string PresentationDocument::LastError() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->live_error.empty()) {
    return impl_->live_error;
  }
  return impl_->error;
}

std::size_t PresentationDocument::SlideCount() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->live_powerpoint_enabled && impl_->live_slide_count > 0) {
    return impl_->live_slide_count;
  }
  return impl_->loaded ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : 0;
}

std::size_t PresentationDocument::CurrentIndex() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->current;
}

bool PresentationDocument::HasNext() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  const auto slide_count = impl_->live_powerpoint_enabled && impl_->live_slide_count > 0
    ? impl_->live_slide_count
    : (impl_->loaded ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : 0);
  return slide_count > 0 && impl_->current + 1 < slide_count;
}

bool PresentationDocument::HasPrevious() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->current > 0;
}

bool PresentationDocument::IsBlackScreen() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->black;
}

void PresentationDocument::Next()
{
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_powerpoint_enabled && impl_->live_ready;
  }
  if (use_live) {
    LivePowerPointSnapshot snapshot;
    std::string error;
    if (RunPowerPointLiveCommand(
          R"(go to next slide (slideshow view of slide show window of targetPresentation))",
          snapshot,
          error)) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->current = snapshot.current_index;
      impl_->live_slide_count = snapshot.slide_count;
      impl_->live_window_title = snapshot.window_title;
      impl_->live_error.clear();
      impl_->black = false;
      impl_->version += 1;
    } else {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->live_error = error;
      impl_->version += 1;
    }
    return;
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded) {
    return;
  }

  const bool has_media_on_current =
    impl_->current < impl_->media_by_slide.size() && !impl_->media_by_slide[impl_->current].empty();
  if (has_media_on_current && !impl_->current_media_triggered) {
    impl_->current_media_triggered = true;
    impl_->version += 1;
    return;
  }

  if (impl_->current + 1 >= static_cast<std::size_t>(impl_->pdf_document.pageCount)) {
    return;
  }
  impl_->current += 1;
  impl_->current_media_triggered = false;
  impl_->version += 1;
}

void PresentationDocument::Previous()
{
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_powerpoint_enabled && impl_->live_ready;
  }
  if (use_live) {
    LivePowerPointSnapshot snapshot;
    std::string error;
    if (RunPowerPointLiveCommand(
          R"(go to previous slide (slideshow view of slide show window of targetPresentation))",
          snapshot,
          error)) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->current = snapshot.current_index;
      impl_->live_slide_count = snapshot.slide_count;
      impl_->live_window_title = snapshot.window_title;
      impl_->live_error.clear();
      impl_->black = false;
      impl_->version += 1;
    } else {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->live_error = error;
      impl_->version += 1;
    }
    return;
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded) {
    return;
  }

  if (impl_->current_media_triggered) {
    impl_->current_media_triggered = false;
    impl_->version += 1;
    return;
  }

  if (impl_->current == 0) {
    return;
  }
  impl_->current -= 1;
  impl_->current_media_triggered = false;
  impl_->version += 1;
}

void PresentationDocument::First()
{
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_powerpoint_enabled && impl_->live_ready;
  }
  if (use_live) {
    LivePowerPointSnapshot snapshot;
    std::string error;
    if (RunPowerPointLiveCommand(
          R"(go to first slide (slideshow view of slide show window of targetPresentation))",
          snapshot,
          error)) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->current = snapshot.current_index;
      impl_->live_slide_count = snapshot.slide_count;
      impl_->live_window_title = snapshot.window_title;
      impl_->live_error.clear();
      impl_->black = false;
      impl_->version += 1;
    } else {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->live_error = error;
      impl_->version += 1;
    }
    return;
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded) {
    return;
  }
  impl_->current_media_triggered = false;
  impl_->current = 0;
  impl_->version += 1;
}

void PresentationDocument::Last()
{
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_powerpoint_enabled && impl_->live_ready;
  }
  if (use_live) {
    LivePowerPointSnapshot snapshot;
    std::string error;
    if (RunPowerPointLiveCommand(
          R"(go to last slide (slideshow view of slide show window of targetPresentation))",
          snapshot,
          error)) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->current = snapshot.current_index;
      impl_->live_slide_count = snapshot.slide_count;
      impl_->live_window_title = snapshot.window_title;
      impl_->live_error.clear();
      impl_->black = false;
      impl_->version += 1;
    } else {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->live_error = error;
      impl_->version += 1;
    }
    return;
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || impl_->pdf_document.pageCount <= 0) {
    return;
  }
  impl_->current_media_triggered = false;
  impl_->current = static_cast<std::size_t>(impl_->pdf_document.pageCount - 1);
  impl_->version += 1;
}

void PresentationDocument::GoTo(std::size_t index)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || index >= static_cast<std::size_t>(impl_->pdf_document.pageCount)) {
    return;
  }
  impl_->current_media_triggered = false;
  impl_->current = index;
  impl_->version += 1;
}

void PresentationDocument::ToggleBlackScreen()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->black = !impl_->black;
  impl_->version += 1;
}

uint64_t PresentationDocument::StateVersion() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->version;
}

uint64_t PresentationDocument::PresentationSeconds() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  auto elapsed = Clock::now() - impl_->started_at;
  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(elapsed).count());
}

std::vector<EmbeddedMedia> PresentationDocument::CurrentMedia() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->live_powerpoint_enabled && impl_->live_ready) {
    return {};
  }
  if (!impl_->loaded || impl_->current >= impl_->media_by_slide.size() || !impl_->current_media_triggered) {
    return {};
  }

  return impl_->media_by_slide[impl_->current];
}

bool PresentationDocument::RenderSlideBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride) const
{
  @autoreleasepool {
    PDFDocument *document = nil;
    bool loading = false;
    bool loaded = false;
    bool live_enabled = false;
    bool live_ready = false;
    bool black = false;
    std::string error;
    std::string live_error;
    std::size_t current = 0;

    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      document = impl_->pdf_document;
      loading = impl_->loading;
      loaded = impl_->loaded;
      live_enabled = impl_->live_powerpoint_enabled;
      live_ready = impl_->live_ready;
      black = impl_->black;
      error = impl_->error;
      live_error = impl_->live_error;
      current = impl_->current;
    }

    NSBitmapImageRep *bitmap = CreateBitmap(width, height);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];

    NSRect canvas = NSMakeRect(0, 0, width, height);
    FillRect(canvas, [NSColor blackColor]);

    if (live_enabled && live_ready && !black) {
      DrawCenteredMessage(@"PPTBridge SK", @"PowerPoint live mode active…", canvas);
    } else if (loaded && !black) {
      DrawPageThumbnail(document, current, canvas);
    } else if (live_enabled && loading) {
      DrawCenteredMessage(@"PPTBridge SK", @"Starting PowerPoint live mode…", canvas);
    } else if (live_enabled && !live_error.empty()) {
      DrawCenteredMessage(@"PPTBridge SK", ToNSString(live_error), canvas);
    } else if (loading) {
      DrawCenteredMessage(@"PPTBridge SK", @"Loading presentation…", canvas);
    } else if (!error.empty()) {
      DrawCenteredMessage(@"PPTBridge SK", ToNSString(error), canvas);
    } else {
      DrawCenteredMessage(@"PPTBridge SK", @"Choose a .pptx in source properties", canvas);
    }

    [NSGraphicsContext restoreGraphicsState];

    out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
    CopyBitmapToBGRA(bitmap, height, out_pixels);
    return true;
  }
}

bool PresentationDocument::RenderPresenterBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride) const
{
  @autoreleasepool {
    PDFDocument *document = nil;
    std::vector<SlideMetadata> slides;
    bool loading = false;
    bool loaded = false;
    bool live_enabled = false;
    bool live_ready = false;
    bool black = false;
    std::string error;
    std::string live_error;
    std::string name;
    std::size_t current = 0;
    std::size_t slide_count = 0;
    uint64_t timer_seconds = 0;

    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      document = impl_->pdf_document;
      slides = impl_->slides;
      loading = impl_->loading;
      loaded = impl_->loaded;
      live_enabled = impl_->live_powerpoint_enabled;
      live_ready = impl_->live_ready;
      black = impl_->black;
      error = impl_->error;
      live_error = impl_->live_error;
      name = impl_->name;
      current = impl_->current;
      slide_count = impl_->live_powerpoint_enabled && impl_->live_slide_count > 0
        ? impl_->live_slide_count
        : (impl_->loaded && impl_->pdf_document ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : 0);
      timer_seconds = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::seconds>(Clock::now() - impl_->started_at).count());
    }

    NSBitmapImageRep *bitmap = CreateBitmap(width, height);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];

    NSRect canvas = NSMakeRect(0, 0, width, height);
    FillRect(canvas, [NSColor colorWithCalibratedRed:0.05 green:0.07 blue:0.10 alpha:1.0]);

    NSRect top_bar = NSMakeRect(0, height - 56, width, 56);
    FillRect(top_bar, [NSColor colorWithCalibratedRed:0.07 green:0.10 blue:0.13 alpha:1.0]);
    DrawLabel(@"PPTBridge SK Presenter", NSMakeRect(24, height - 40, 320, 24), [NSColor whiteColor], [NSFont boldSystemFontOfSize:20]);
    DrawLabel(ToNSString(name), NSMakeRect(24, height - 62, width - 320, 18), [NSColor colorWithWhite:0.65 alpha:1.0], [NSFont systemFontOfSize:12 weight:NSFontWeightRegular]);
    DrawLabel(ToNSString(FormatTimer(timer_seconds)), NSMakeRect(width - 120, height - 40, 96, 24), [NSColor whiteColor], [NSFont monospacedDigitSystemFontOfSize:20 weight:NSFontWeightSemibold]);

    if (black) {
      NSRect badge = NSMakeRect(width - 260, height - 45, 120, 28);
      [[NSColor colorWithCalibratedRed:0.92 green:0.28 blue:0.34 alpha:1.0] setFill];
      [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:14 yRadius:14] fill];
      DrawLabel(@"BLACK LIVE", NSInsetRect(badge, 14, 5), [NSColor whiteColor], [NSFont boldSystemFontOfSize:13]);
    }

    if (!loaded) {
      NSString *subtitle = nil;
      if (live_enabled && live_ready) {
        subtitle = @"Live slideshow is ready. Loading presenter notes and thumbnails…";
      } else if (live_enabled && loading) {
        subtitle = @"Starting PowerPoint live mode and loading presenter notes…";
      } else if (live_enabled && !live_error.empty()) {
        subtitle = ToNSString(live_error);
      } else if (loading) {
        subtitle = @"Loading presentation…";
      } else {
        subtitle = error.empty() ? @"Choose a .pptx in source properties" : ToNSString(error);
      }
      DrawCenteredMessage(@"PPTBridge SK", subtitle, NSMakeRect(0, 0, width, height - 56));
      [NSGraphicsContext restoreGraphicsState];
      out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
      CopyBitmapToBGRA(bitmap, height, out_pixels);
      return true;
    }

    const std::size_t pdf_slide_count = document ? static_cast<std::size_t>(document.pageCount) : 0;
    if (pdf_slide_count == 0) {
      DrawCenteredMessage(@"PPTBridge SK", @"Presenter thumbnails are not available for this deck yet.", NSMakeRect(0, 0, width, height - 56));
      [NSGraphicsContext restoreGraphicsState];
      out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
      CopyBitmapToBGRA(bitmap, height, out_pixels);
      return true;
    }

    current = std::min(current, pdf_slide_count - 1);
    const std::size_t shown_slide_count = slide_count > 0 ? slide_count : pdf_slide_count;

    CGFloat margin = 18.0;
    CGFloat right_width = std::max<CGFloat>(320.0, width * 0.28);
    NSRect left = NSMakeRect(margin, margin + 60, width - right_width - margin * 3, height - 56 - margin * 2 - 60);
    NSRect right = NSMakeRect(NSMaxX(left) + margin, margin + 60, right_width, height - 56 - margin * 2 - 60);

    FillRect(left, [NSColor blackColor]);
    DrawPageThumbnail(document, current, left);

    NSRect slide_count_rect = NSMakeRect(left.origin.x, 18, 180, 30);
    DrawLabel(
      [NSString stringWithFormat:@"Slide %lu / %lu",
        static_cast<unsigned long>(current + 1),
        static_cast<unsigned long>(shown_slide_count)],
      slide_count_rect,
      [NSColor colorWithWhite:0.75 alpha:1.0],
      [NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightMedium]);

    NSRect next_box = NSMakeRect(right.origin.x, right.origin.y + right.size.height - 220, right.size.width, 200);
    [[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.15 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:next_box xRadius:18 yRadius:18] fill];
    DrawLabel(@"Next Slide", NSMakeRect(next_box.origin.x + 16, NSMaxY(next_box) - 28, 200, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);
    if (current + 1 < pdf_slide_count) {
      DrawPageThumbnail(document, current + 1, NSInsetRect(next_box, 14, 18));
    } else {
      DrawCenteredMessage(@"End", @"No next slide", next_box);
    }

    NSRect notes_box = NSMakeRect(right.origin.x, right.origin.y, right.size.width, right.size.height - 236);
    [[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.15 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:notes_box xRadius:18 yRadius:18] fill];
    DrawLabel(@"Presenter Notes", NSMakeRect(notes_box.origin.x + 16, NSMaxY(notes_box) - 28, 240, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);

    std::string notes;
    if (current < slides.size()) {
      notes = slides[current].notes;
    }
    NSString *notes_text = notes.empty() ? @"No presenter notes found in the PPTX notes page for this slide." : ToNSString(notes);
    NSDictionary *notes_attrs = @{
      NSForegroundColorAttributeName : notes.empty() ? [NSColor colorWithWhite:0.55 alpha:1.0] : [NSColor colorWithWhite:0.95 alpha:1.0],
      NSFontAttributeName : [NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightRegular],
    };
    [notes_text drawInRect:NSInsetRect(notes_box, 16, 20) withAttributes:notes_attrs];

    [NSGraphicsContext restoreGraphicsState];

    out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
    CopyBitmapToBGRA(bitmap, height, out_pixels);
    return true;
  }
}

}  // namespace pptbridge
