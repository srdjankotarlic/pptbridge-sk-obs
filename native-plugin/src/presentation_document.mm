#import "presentation_document.hpp"

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

#include <obs-module.h>

#include <csignal>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <thread>
#include <unordered_map>

namespace fs = std::filesystem;

namespace pptbridge {

namespace {

using Clock = std::chrono::steady_clock;

constexpr NSTimeInterval kDefaultTaskTimeoutSeconds = 300.0;
constexpr NSTimeInterval kLibreOfficeExportTimeoutSeconds = 90.0;
constexpr NSTimeInterval kPowerPointExportTimeoutSeconds = 180.0;
constexpr int kPowerPointAppleEventTimeoutSeconds = 165;
constexpr NSTimeInterval kLiveStartTaskTimeoutSeconds = 30.0;
constexpr NSTimeInterval kLiveTaskTimeoutSeconds = 12.0;
constexpr NSTimeInterval kStopTaskTimeoutSeconds = 8.0;
constexpr NSTimeInterval kTerminateGraceSeconds = 2.0;
constexpr NSTimeInterval kPipeDrainGraceSeconds = 2.0;
constexpr const char *kPowerPointBundleIdentifier = "com.microsoft.Powerpoint";

NSString *ToNSString(const std::string &value)
{
  return [NSString stringWithUTF8String:value.c_str()];
}

std::string ToStdString(NSString *value)
{
  return value ? std::string(value.UTF8String) : std::string();
}

std::string NormalizePathForCacheIdentity(const std::string &path)
{
  NSString *path_ns = ToNSString(path);
  if (!path_ns) {
    return path;
  }

  // macOS may hand us visually identical file names in different Unicode
  // normalization forms (for example "Guć" vs "Guć"). Normalize before
  // hashing so one deck maps to one cache directory.
  NSString *standardized = [path_ns stringByStandardizingPath];
  NSString *precomposed = [standardized precomposedStringWithCanonicalMapping];
  return ToStdString(precomposed ?: standardized ?: path_ns);
}

NSString *JoinLines(NSArray<NSString *> *lines)
{
  return [lines componentsJoinedByString:@"\n"];
}

NSString *ReadZipEntry(const std::string &pptx_path, const std::string &entry_path);
NSArray<NSXMLNode *> *XPath(NSXMLNode *node, NSString *query);

void *LiveQueueSpecificKey()
{
  static int key;
  return &key;
}

bool RunTask(
  NSString *launch_path,
  NSArray<NSString *> *arguments,
  std::string &std_out,
  std::string &std_err,
  int &exit_code,
  NSTimeInterval timeout_seconds = kDefaultTaskTimeoutSeconds)
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
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *) {
      dispatch_semaphore_signal(finished);
    };

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
    } @catch (NSException *exception) {
      std_err = ToStdString(exception.reason ?: @"Unknown task launch error");
      return false;
    }

    @try {
      [[out_pipe fileHandleForWriting] closeFile];
      [[err_pipe fileHandleForWriting] closeFile];
    } @catch (NSException *) {
      // The child process owns its inherited write handles; parent-side close
      // failures should not mask the real process result.
    }

    NSFileHandle *stdout_handle = [out_pipe fileHandleForReading];
    NSFileHandle *stderr_handle = [err_pipe fileHandleForReading];
    dispatch_queue_t io_queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_group_t io_group = dispatch_group_create();
    __block std::string stdout_text;
    __block std::string stderr_text;
    __block std::string stdout_read_error;
    __block std::string stderr_read_error;

    dispatch_group_async(io_group, io_queue, ^{
      @autoreleasepool {
        @try {
          NSData *data = [stdout_handle readDataToEndOfFile];
          NSString *text = [[NSString alloc] initWithData:(data ?: [NSData data]) encoding:NSUTF8StringEncoding];
          stdout_text = ToStdString(text ?: @"");
#if !__has_feature(objc_arc)
          [text release];
#endif
        } @catch (NSException *exception) {
          stdout_read_error = ToStdString(exception.reason ?: @"Could not read process stdout.");
        }
      }
    });

    dispatch_group_async(io_group, io_queue, ^{
      @autoreleasepool {
        @try {
          NSData *data = [stderr_handle readDataToEndOfFile];
          NSString *text = [[NSString alloc] initWithData:(data ?: [NSData data]) encoding:NSUTF8StringEncoding];
          stderr_text = ToStdString(text ?: @"");
#if !__has_feature(objc_arc)
          [text release];
#endif
        } @catch (NSException *exception) {
          stderr_read_error = ToStdString(exception.reason ?: @"Could not read process stderr.");
        }
      }
    });

    const dispatch_time_t timeout_deadline = timeout_seconds > 0
      ? dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(timeout_seconds * NSEC_PER_SEC))
      : DISPATCH_TIME_FOREVER;
    bool timed_out = dispatch_semaphore_wait(finished, timeout_deadline) != 0;
    if (timed_out) {
      [task terminate];
      const dispatch_time_t terminate_deadline =
        dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(kTerminateGraceSeconds * NSEC_PER_SEC));
      if (dispatch_semaphore_wait(finished, terminate_deadline) != 0 && task.isRunning) {
        kill(task.processIdentifier, SIGKILL);
        dispatch_semaphore_wait(finished, terminate_deadline);
      }
    }

    const dispatch_time_t drain_deadline =
      dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(kPipeDrainGraceSeconds * NSEC_PER_SEC));
    bool pipes_drained = dispatch_group_wait(io_group, drain_deadline) == 0;
    if (!pipes_drained) {
      @try {
        [stdout_handle closeFile];
        [stderr_handle closeFile];
      } @catch (NSException *) {
      }
      pipes_drained = dispatch_group_wait(io_group, drain_deadline) == 0;
    }

    if (pipes_drained) {
      std_out = stdout_text;
      std_err = stderr_text;
      if (!stdout_read_error.empty() || !stderr_read_error.empty()) {
        if (!std_err.empty()) {
          std_err += "\n";
        }
        if (!stdout_read_error.empty()) {
          std_err += stdout_read_error;
        }
        if (!stderr_read_error.empty()) {
          if (!stdout_read_error.empty()) {
            std_err += "\n";
          }
          std_err += stderr_read_error;
        }
      }
    } else {
      std_out.clear();
      std_err = "Process output could not be drained safely.";
    }
    if (timed_out) {
      if (!std_err.empty()) {
        std_err += "\n";
      }
      std_err += "Process timed out after " + std::to_string(static_cast<int>(timeout_seconds)) + " seconds.";
      return false;
    }

    exit_code = task.terminationStatus;
    return stdout_read_error.empty() && stderr_read_error.empty();
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

std::string LiveRecoveryErrorMessage(const std::string &detail)
{
  std::string message =
    "PowerPoint slideshow is not available. Click Start / Restart PowerPoint Live Mode in source properties to recover.";
  const std::string trimmed = TrimWhitespace(detail);
  if (!trimmed.empty()) {
    message += " Last PowerPoint response: " + trimmed;
  }
  return message;
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

std::string AppleScriptStringLiteral(const std::string &value)
{
  std::string literal = "\"";
  for (char ch : value) {
    if (ch == '\\' || ch == '"') {
      literal.push_back('\\');
    }
    literal.push_back(ch);
  }
  literal.push_back('"');
  return literal;
}

std::string AppleScriptListLiteral(const std::vector<std::string> &values)
{
  std::string literal = "{";
  for (std::size_t index = 0; index < values.size(); ++index) {
    if (index > 0) {
      literal += ", ";
    }
    literal += AppleScriptStringLiteral(values[index]);
  }
  literal += "}";
  return literal;
}

std::string PowerPointApplicationTellLine(const std::string &powerpoint_bundle)
{
  const auto bundle = powerpoint_bundle.empty() ? FindPowerPointBundle() : powerpoint_bundle;
  if (bundle.empty()) {
    return "tell application \"Microsoft PowerPoint\"";
  }
  // AppleScript cannot target a POSIX .app path directly in a tell block.
  // Keep bundle discovery as validation, then use the display name because
  // `osascript file.applescript` resolves it more reliably than application id.
  return "tell application \"Microsoft PowerPoint\"";
}

std::string PowerPointTerminologyWrapped(const std::string &source)
{
  return "using terms from application \"Microsoft PowerPoint\"\n" + source + "\nend using terms from\n";
}

bool IsPowerPointRunning()
{
  NSArray<NSRunningApplication *> *apps =
    [NSRunningApplication runningApplicationsWithBundleIdentifier:@(kPowerPointBundleIdentifier)];
  return apps.count > 0;
}

bool WaitForPowerPointExit(NSTimeInterval timeout_seconds)
{
  const auto deadline = Clock::now() +
    std::chrono::milliseconds(static_cast<int64_t>(timeout_seconds * 1000.0));
  while (Clock::now() < deadline) {
    if (!IsPowerPointRunning()) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return !IsPowerPointRunning();
}

bool TerminatePowerPointApplications(bool force_after_grace)
{
  NSArray<NSRunningApplication *> *apps =
    [NSRunningApplication runningApplicationsWithBundleIdentifier:@(kPowerPointBundleIdentifier)];
  if (apps.count == 0) {
    return true;
  }

  for (NSRunningApplication *app in apps) {
    [app terminate];
  }
  if (WaitForPowerPointExit(kTerminateGraceSeconds)) {
    return true;
  }
  if (!force_after_grace) {
    return false;
  }

  apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@(kPowerPointBundleIdentifier)];
  for (NSRunningApplication *app in apps) {
    [app forceTerminate];
  }
  return WaitForPowerPointExit(kTerminateGraceSeconds);
}

std::vector<std::string> SplitLines(const std::string &value);
bool RunAppleScriptLines(
  const std::vector<std::string> &lines,
  std::string &std_out,
  std::string &std_err,
  int &exit_code,
  NSTimeInterval timeout_seconds = kDefaultTaskTimeoutSeconds);

bool QueryPowerPointOpenCounts(int &presentation_count, int &slide_show_count)
{
  presentation_count = -1;
  slide_show_count = -1;
  if (!IsPowerPointRunning()) {
    presentation_count = 0;
    slide_show_count = 0;
    return true;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const auto tell_powerpoint = PowerPointApplicationTellLine({});
  const bool ok = RunAppleScriptLines(
      {
        tell_powerpoint,
      "return ((count of presentations) as text) & \",\" & ((count of slide show windows) as text)",
        "end tell",
      },
    std_out,
    std_err,
    exit_code,
    kStopTaskTimeoutSeconds);

  if (!ok || exit_code != 0) {
    return false;
  }

  auto counts_text = TrimWhitespace(std_out);
  std::replace(counts_text.begin(), counts_text.end(), ',', '\n');
  const auto lines = SplitLines(counts_text);
  if (lines.size() < 2) {
    return false;
  }

  try {
    presentation_count = std::stoi(lines[0]);
    slide_show_count = std::stoi(lines[1]);
    return true;
  } catch (const std::exception &) {
    return false;
  }
}

bool RestartPowerPointIfIdleForLiveRetry(bool allow_unresponsive_restart)
{
  int presentation_count = -1;
  int slide_show_count = -1;
  if (!QueryPowerPointOpenCounts(presentation_count, slide_show_count)) {
    return allow_unresponsive_restart ? TerminatePowerPointApplications(true) : false;
  }
  if (presentation_count != 0 || slide_show_count != 0) {
    return false;
  }
  if (!IsPowerPointRunning()) {
    return true;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const auto tell_powerpoint = PowerPointApplicationTellLine({});
  const bool quit_ok = RunAppleScriptLines(
    { tell_powerpoint + " to quit saving no" },
    std_out,
    std_err,
    exit_code,
    kStopTaskTimeoutSeconds);
  if (!quit_ok || exit_code != 0) {
    return TerminatePowerPointApplications(true);
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(700));
  return !IsPowerPointRunning() || TerminatePowerPointApplications(true);
}

std::string DeckCacheHash(const std::string &pptx_path)
{
  const auto normalized_path = NormalizePathForCacheIdentity(pptx_path);
  std::stringstream stream;
  stream << std::hash<std::string>{}(normalized_path);
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

  if (!RunTask(soffice_ns, arguments, std_out, std_err, exit_code, kLibreOfficeExportTimeoutSeconds) ||
      exit_code != 0) {
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

std::string PowerPointAppleScriptSaveAsSource(const std::string &powerpoint_bundle)
{
  const auto tell_powerpoint = PowerPointApplicationTellLine(powerpoint_bundle);
  const auto apple_event_timeout = std::to_string(kPowerPointAppleEventTimeoutSeconds);
  const std::string source = std::string(R"APPLESCRIPT(
on normalize_posix_path(candidate)
	try
		return POSIX path of ((POSIX file candidate) as alias)
	on error
		try
			return POSIX path of (candidate as alias)
		on error
			try
				return candidate as text
			on error
				return ""
			end try
		end try
	end try
end normalize_posix_path

on active_presentation_path()
)APPLESCRIPT") + "\t" + tell_powerpoint + R"APPLESCRIPT(
		try
			return my normalize_posix_path((full name of active presentation) as text)
		end try
		try
			return my normalize_posix_path((path of active presentation) as text)
		end try
	end tell
	return ""
end active_presentation_path

on wait_for_active_presentation(expected_path, max_wait_seconds)
	repeat max_wait_seconds times
		if my active_presentation_path() is expected_path then
)APPLESCRIPT" + "\t\t\t" + tell_powerpoint + R"APPLESCRIPT(
				return active presentation
			end tell
		end if
		delay 1
	end repeat
	error "PowerPoint opened the file, but the staged presentation did not become active."
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
)APPLESCRIPT" + "\twith timeout of " + apple_event_timeout + R"APPLESCRIPT( seconds
)APPLESCRIPT" + "\t\t" + tell_powerpoint + R"APPLESCRIPT(
			try
				close opened_presentation saving no
			end try
	end tell
	end timeout
end close_opened_presentation

on run argv
	if (count of argv) is not 2 then error "Expected input and output paths."
	set raw_input_path to item 1 of argv
	set input_path to my normalize_posix_path(raw_input_path)
	if input_path is "" then set input_path to raw_input_path
	set output_path to item 2 of argv

	try
)APPLESCRIPT" + "\t\twith timeout of " + apple_event_timeout + R"APPLESCRIPT( seconds
)APPLESCRIPT" + "\t\t\t" + tell_powerpoint + R"APPLESCRIPT(
				open (POSIX file input_path)
		end tell
		end timeout
		set opened_presentation to my wait_for_active_presentation(input_path, 20)
)APPLESCRIPT" + "\t\twith timeout of " + apple_event_timeout + R"APPLESCRIPT( seconds
)APPLESCRIPT" + "\t\t\t" + tell_powerpoint + R"APPLESCRIPT(
				save active presentation in (POSIX file output_path) as save as PDF
		end tell
		end timeout
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
  return PowerPointTerminologyWrapped(source);
}

bool RunAppleScriptFile(
  const std::string &cache_dir,
  const std::string &script_name,
  const std::string &script_source,
  const std::vector<std::string> &script_arguments,
  std::string &std_out,
  std::string &std_err,
  int &exit_code,
  NSTimeInterval timeout_seconds = kDefaultTaskTimeoutSeconds)
{
  auto script_path = fs::path(cache_dir) / script_name;
  std::string write_error;
  if (!WriteUtf8TextFile(ToNSString(script_path.string()), ToNSString(script_source), write_error)) {
    std_err = write_error;
    std_out.clear();
    exit_code = -1;
    return false;
  }

  const std::vector<std::string> wrapper_lines = {
    "set pptbridge_script_args to " + AppleScriptListLiteral(script_arguments),
    "set pptbridge_script_file to POSIX file " + AppleScriptStringLiteral(script_path.string()),
    "run script pptbridge_script_file with parameters pptbridge_script_args",
  };

  const bool ok = RunAppleScriptLines(
    wrapper_lines,
    std_out,
    std_err,
    exit_code,
    timeout_seconds);
  if (std::getenv("PPTBRIDGE_DEBUG_APPLESCRIPT")) {
    blog(
      LOG_INFO,
      "[PPTBridge] AppleScript debug: script=%s exit=%d ok=%s",
      script_path.string().c_str(),
      exit_code,
      ok ? "true" : "false");
    for (const auto &line : wrapper_lines) {
      blog(LOG_INFO, "[PPTBridge] AppleScript debug wrapper: %s", line.c_str());
    }
  }
  return ok;
}

bool RunAppleScriptLines(
  const std::vector<std::string> &lines,
  std::string &std_out,
  std::string &std_err,
  int &exit_code,
  NSTimeInterval timeout_seconds)
{
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  for (const auto &line : lines) {
    [arguments addObject:@"-e"];
    [arguments addObject:ToNSString(line)];
  }

  return RunTask(@"/usr/bin/osascript", arguments, std_out, std_err, exit_code, timeout_seconds);
}

struct LivePowerPointSnapshot {
  std::string window_title;
  std::string presentation_path;
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
    snapshot.presentation_path = lines.size() > 3 ? lines[3] : "";
    snapshot.current_index = slide_number > 0 ? static_cast<std::size_t>(slide_number - 1) : 0;
    snapshot.slide_count = static_cast<std::size_t>(slide_count);
    return true;
  } catch (const std::exception &) {
    out_error = "PowerPoint live mode returned invalid slide information.";
    return false;
  }
}

fs::path StagedPowerPointLivePath(const std::string &pptx_path, const fs::path &work_dir)
{
  const fs::path input(pptx_path);
  const std::string hash = DeckCacheHash(pptx_path);
  const std::string short_hash = hash.substr(0, std::min<std::size_t>(hash.size(), 8));
  const std::string stem = input.stem().string().empty() ? "deck" : input.stem().string();
  const std::string extension = input.extension().string().empty() ? ".pptx" : input.extension().string();
  return work_dir / (stem + " - PPTBridge " + short_hash + extension);
}

fs::path PowerPointLiveWorkDirectory(const std::string &pptx_path)
{
  // PowerPoint on macOS can refuse or hang when AppleScript opens .pptx files
  // staged under another app's Application Support tree. A per-deck temp
  // folder keeps live-mode staging readable by PowerPoint while the static PDF
  // cache remains in Application Support for OBS/PDFKit.
  return fs::path(ToStdString(NSTemporaryDirectory())) / "pptbridge-sk-live" / DeckCacheHash(pptx_path);
}

std::string PowerPointAppleScriptLiveHandlers(const std::string &powerpoint_bundle)
{
  const auto tell_powerpoint = PowerPointApplicationTellLine(powerpoint_bundle);
  return std::string(R"APPLESCRIPT(
on normalize_posix_path(candidate)
	try
		return POSIX path of (candidate as alias)
	on error
		try
			return candidate as text
		on error
			return ""
		end try
	end try
end normalize_posix_path

on snapshot_for_path(target_path)
)APPLESCRIPT") + "\t" + tell_powerpoint + R"APPLESCRIPT(
		set targetPresentation to missing value
		set presentationPath to ""
		repeat with i from 1 to count of presentations
			set candidatePresentation to presentation i
			set candidatePath to ""
			try
				set candidatePath to my normalize_posix_path((full name of candidatePresentation) as text)
			end try
			if candidatePath is "" then
				try
					set candidatePath to my normalize_posix_path((path of candidatePresentation) as text)
				end try
			end if
			if candidatePath is target_path then
				set targetPresentation to candidatePresentation
				set presentationPath to candidatePath
				exit repeat
			end if
		end repeat

		if targetPresentation is missing value then error "PowerPoint presentation is not open for this deck."
		set targetWindow to slide show window of targetPresentation
		set windowTitle to name of targetWindow
		set slideNumber to slide index of slide of slideshow view of targetWindow
		set slideCount to count of slides of targetPresentation
		if presentationPath is "" then set presentationPath to target_path
		return windowTitle & linefeed & (slideNumber as text) & linefeed & (slideCount as text) & linefeed & presentationPath
	end tell
end snapshot_for_path

)APPLESCRIPT";
}

std::string PowerPointAppleScriptLiveStartSource(const std::string &powerpoint_bundle)
{
  const auto tell_powerpoint = PowerPointApplicationTellLine(powerpoint_bundle);
  const std::string source = PowerPointAppleScriptLiveHandlers(powerpoint_bundle) + R"APPLESCRIPT(
on wait_for_slide_show_window(target_path, max_wait_seconds)
	repeat (max_wait_seconds * 10) times
		try
			return my snapshot_for_path(target_path)
		end try
		delay 0.1
	end repeat
	error "PowerPoint live slideshow window did not appear."
end wait_for_slide_show_window

on run argv
	if (count of argv) is not 1 then error "Expected PowerPoint input path."
	set input_path to my normalize_posix_path(item 1 of argv)

)APPLESCRIPT" + "\t" + tell_powerpoint + R"APPLESCRIPT(
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

	return my wait_for_slide_show_window(input_path, 20)
end run
	)APPLESCRIPT";
  return PowerPointTerminologyWrapped(source);
}

std::string PowerPointAppleScriptLiveQuerySource(const std::string &powerpoint_bundle)
{
  const std::string source = PowerPointAppleScriptLiveHandlers(powerpoint_bundle) + R"APPLESCRIPT(
on run argv
	if (count of argv) is not 1 then error "Expected PowerPoint input path."
	set input_path to my normalize_posix_path(item 1 of argv)
	return my snapshot_for_path(input_path)
end run
	)APPLESCRIPT";
  return PowerPointTerminologyWrapped(source);
}

std::string PowerPointAppleScriptLiveStopSource(const std::string &powerpoint_bundle)
{
  const auto tell_powerpoint = PowerPointApplicationTellLine(powerpoint_bundle);
  const std::string source = PowerPointAppleScriptLiveHandlers(powerpoint_bundle) + R"APPLESCRIPT(
on run argv
	if (count of argv) is less than 1 then error "Expected PowerPoint input path."
	set input_path to my normalize_posix_path(item 1 of argv)
	set target_title to ""
	if (count of argv) is greater than 1 then set target_title to item 2 of argv
	set did_close to false

)APPLESCRIPT" + "\t" + tell_powerpoint + R"APPLESCRIPT(
		set targetPresentation to missing value
		repeat with i from 1 to count of presentations
			set candidatePresentation to presentation i
			set candidatePath to ""
			try
				set candidatePath to my normalize_posix_path((full name of candidatePresentation) as text)
			end try
			if candidatePath is "" then
				try
					set candidatePath to my normalize_posix_path((path of candidatePresentation) as text)
				end try
			end if
			if candidatePath is input_path then
				set targetPresentation to candidatePresentation
				exit repeat
			end if
		end repeat
		if targetPresentation is not missing value then
			try
				tell slideshow view of slide show window of targetPresentation to exit slide show
				set did_close to true
			end try
		else if target_title is not "" then
			try
				repeat with targetWindow in slide show windows
					if ((name of targetWindow) as text) is target_title then
						tell slideshow view of targetWindow to exit slide show
						set did_close to true
						exit repeat
					end if
				end repeat
			end try
		end if

		if did_close then
			delay 0.2
			try
				if targetPresentation is not missing value then close targetPresentation saving no
			end try
			try
				if (count of presentations) is 0 then quit
			end try
			return "closed"
		end if
	end tell

	return "not running"
end run
	)APPLESCRIPT";
  return PowerPointTerminologyWrapped(source);
}

bool QueryPowerPointLiveState(
  const std::string &cache_dir,
  const std::string &presentation_path,
  LivePowerPointSnapshot &snapshot,
  std::string &out_error)
{
  if (presentation_path.empty()) {
    out_error = "PowerPoint live query has no target presentation path.";
    return false;
  }
  const auto powerpoint_bundle = FindPowerPointBundle();
  if (powerpoint_bundle.empty()) {
    out_error = "Microsoft PowerPoint was not found.";
    return false;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool ok = RunAppleScriptFile(
    cache_dir.empty() ? CacheDirectoryForDeck(presentation_path) : cache_dir,
    "pptbridge_powerpoint_live_query.applescript",
    PowerPointAppleScriptLiveQuerySource(powerpoint_bundle),
    { presentation_path },
    std_out,
    std_err,
    exit_code,
    kLiveTaskTimeoutSeconds);

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
  const bool powerpoint_was_running_before_start = IsPowerPointRunning();

  std::error_code error;
  auto work_dir = PowerPointLiveWorkDirectory(pptx_path);
  fs::create_directories(work_dir, error);
  const bool can_stage_copy = !error;
  const auto original_input = fs::path(pptx_path);
  const auto copied_input = StagedPowerPointLivePath(pptx_path, work_dir);

  // Fast path: if PowerPoint already has this exact staged deck running
  // (for example OBS was restarted while PowerPoint stayed open), reattach
  // to that session. Do not use PowerPoint's active presentation here:
  // multi-deck shows often have a different slideshow active.
  {
    std::string query_error;
    LivePowerPointSnapshot existing;
    if (QueryPowerPointLiveState(cache_dir, original_input.string(), existing, query_error) &&
        !existing.window_title.empty()) {
      snapshot = existing;
      return true;
    }

    std::error_code exists_error;
    if (fs::exists(copied_input, exists_error)) {
      if (QueryPowerPointLiveState(cache_dir, copied_input.string(), existing, query_error) &&
          !existing.window_title.empty()) {
        snapshot = existing;
        return true;
      }
    }
  }

  bool staged_copy_available = false;
  if (can_stage_copy) {
    error.clear();
    fs::copy_file(pptx_path, copied_input, fs::copy_options::overwrite_existing, error);
    if (!error) {
      staged_copy_available = true;
    } else {
      // Copy may fail if PowerPoint still has the destination open from a
      // previous run (leaves a ~$...pptx lock file next to it). If we still
      // have a usable copy from an earlier session, reuse it; otherwise try
      // a tmp-dir rename, and only then give up on the fallback copy.
      std::error_code exists_error;
      if (fs::exists(copied_input, exists_error)) {
        staged_copy_available = true;
      } else {
        auto tmp_staged = work_dir / ("pptbridge_stage_" + copied_input.filename().string());
        error.clear();
        fs::copy_file(pptx_path, tmp_staged, fs::copy_options::overwrite_existing, error);
        staged_copy_available = !error;
      }
    }
  }

  auto start_once = [&](const std::string &input_path, std::string &attempt_error) -> bool {
    std::string std_out;
    std::string std_err;
    int exit_code = 0;
    const bool launched = RunAppleScriptFile(
      cache_dir,
      "pptbridge_powerpoint_live_start.applescript",
      PowerPointAppleScriptLiveStartSource(powerpoint_bundle),
      { input_path },
      std_out,
      std_err,
      exit_code,
      kLiveStartTaskTimeoutSeconds);

    if (!launched || exit_code != 0) {
      attempt_error = "PowerPoint live mode failed to start: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
      return false;
    }

    return ParseLivePowerPointOutput(std_out, snapshot, attempt_error);
  };

  auto start_with_retry = [&](const std::string &input_path, const char *label, std::string &attempt_error) -> bool {
    if (start_once(input_path, attempt_error)) {
      return true;
    }

    if (RestartPowerPointIfIdleForLiveRetry(!powerpoint_was_running_before_start)) {
      blog(
        LOG_WARNING,
        "[PPTBridge] PowerPoint live start failed once for '%s' using %s; restarted idle PowerPoint and retrying",
        pptx_path.c_str(),
        label);
      std::string retry_error;
      if (start_once(input_path, retry_error)) {
        return true;
      }
      attempt_error += " Retry after idle PowerPoint restart also failed: " + retry_error;
    }
    return false;
  };

  std::string first_error;
  if (start_with_retry(original_input.string(), "original deck path", first_error)) {
    return true;
  }

  if (staged_copy_available) {
    std::string staged_error;
    if (start_with_retry(copied_input.string(), "staged deck copy", staged_error)) {
      return true;
    }
    out_error = first_error + " Staged fallback also failed: " + staged_error;
  } else {
    out_error = first_error;
  }
  return false;
}

bool StopPowerPointLiveSession(
  const std::string &cache_dir,
  const std::string &presentation_path,
  const std::string &window_title,
  std::string &out_error)
{
  if (presentation_path.empty() && window_title.empty()) {
    return true;
  }
  if (!IsPowerPointRunning()) {
    return true;
  }
  const auto powerpoint_bundle = FindPowerPointBundle();
  if (powerpoint_bundle.empty()) {
    out_error = "Microsoft PowerPoint was not found.";
    return false;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool stopped = RunAppleScriptFile(
    cache_dir.empty()
      ? CacheDirectoryForDeck(!presentation_path.empty() ? presentation_path : window_title)
      : cache_dir,
    "pptbridge_powerpoint_live_stop.applescript",
    PowerPointAppleScriptLiveStopSource(powerpoint_bundle),
    { presentation_path, window_title },
    std_out,
    std_err,
    exit_code,
    kStopTaskTimeoutSeconds);

  if (!stopped || exit_code != 0) {
    out_error = "PowerPoint live mode failed to stop: " + BuildTaskErrorMessage(std_out, std_err, exit_code);
    return false;
  }

  return true;
}

std::string PowerPointAppleScriptLiveCommandSource(
  const std::string &command_line,
  const std::string &powerpoint_bundle)
{
  std::string source = PowerPointAppleScriptLiveHandlers(powerpoint_bundle) + R"APPLESCRIPT(
on run argv
	if (count of argv) is not 1 then error "Expected PowerPoint input path."
	set input_path to my normalize_posix_path(item 1 of argv)
)APPLESCRIPT";
  if (!command_line.empty()) {
    source += "\t" + PowerPointApplicationTellLine(powerpoint_bundle) + "\n\t\t";
    source += R"(set targetPresentation to missing value
		repeat with i from 1 to count of presentations
			set candidatePresentation to presentation i
			set candidatePath to ""
			try
				set candidatePath to my normalize_posix_path((full name of candidatePresentation) as text)
			end try
			if candidatePath is "" then
				try
					set candidatePath to my normalize_posix_path((path of candidatePresentation) as text)
				end try
			end if
			if candidatePath is input_path then
				set targetPresentation to candidatePresentation
				exit repeat
			end if
		end repeat
		if targetPresentation is missing value then error "PowerPoint presentation is not open for this deck."
		)";
    source += command_line;
    source += "\n\tend tell\n\tdelay 0.05\n";
  }
  source += R"APPLESCRIPT(
	return my snapshot_for_path(input_path)
end run
	)APPLESCRIPT";
  return PowerPointTerminologyWrapped(source);
}

bool RunPowerPointLiveCommand(
  const std::string &cache_dir,
  const std::string &presentation_path,
  const std::string &command_line,
  LivePowerPointSnapshot &snapshot,
  std::string &out_error)
{
  if (presentation_path.empty()) {
    out_error = "PowerPoint live command has no target presentation path.";
    return false;
  }
  const auto powerpoint_bundle = FindPowerPointBundle();
  if (powerpoint_bundle.empty()) {
    out_error = "Microsoft PowerPoint was not found.";
    return false;
  }

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool ok = RunAppleScriptFile(
    cache_dir.empty() ? CacheDirectoryForDeck(presentation_path) : cache_dir,
    "pptbridge_powerpoint_live_command.applescript",
    PowerPointAppleScriptLiveCommandSource(command_line, powerpoint_bundle),
    { presentation_path },
    std_out,
    std_err,
    exit_code,
    kLiveTaskTimeoutSeconds);
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
    PowerPointAppleScriptSaveAsSource(powerpoint_bundle),
    { copied_input.string(), output_pdf.string() },
    std_out,
    std_err,
    exit_code,
    kPowerPointExportTimeoutSeconds);

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
  std::string &out_error,
  bool allow_powerpoint_export = true)
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

  std::string libreoffice_error;
  if (ConvertPptxToPdfWithLibreOffice(pptx_path, cache_dir, out_pdf_path, libreoffice_error)) {
    return true;
  }

  blog(
    LOG_WARNING,
    "[PPTBridge] LibreOffice export failed for '%s'%s%s",
    pptx_path.c_str(),
    libreoffice_error.empty() ? "" : ": ",
    libreoffice_error.c_str());

  std::string powerpoint_error;
  if (allow_powerpoint_export && !FindPowerPointBundle().empty()) {
    if (ConvertPptxToPdfWithPowerPoint(pptx_path, cache_dir, out_pdf_path, powerpoint_error)) {
      return true;
    }

    blog(
      LOG_WARNING,
      "[PPTBridge] PowerPoint fallback export failed for '%s': %s",
      pptx_path.c_str(),
      powerpoint_error.c_str());
  }

  out_error = "LibreOffice export failed: " +
    (libreoffice_error.empty() ? std::string("LibreOffice was not available.") : libreoffice_error);
  if (allow_powerpoint_export) {
    out_error += " PowerPoint fallback failed: " +
      (powerpoint_error.empty() ? std::string("PowerPoint was not found.") : powerpoint_error);
  } else {
    out_error += " PowerPoint fallback is disabled until manual live mode is started.";
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

std::vector<SlideMetadata> PlaceholderDeckMetadata(std::size_t slide_count, bool is_pdf_source)
{
  std::vector<SlideMetadata> result(slide_count);
  const char *prefix = is_pdf_source ? "Page " : "Slide ";
  for (std::size_t index = 0; index < slide_count; ++index) {
    result[index].title = std::string(prefix) + std::to_string(index + 1);
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

NSRect AspectFillRect(NSSize content_size, NSRect bounds)
{
  if (content_size.width <= 0 || content_size.height <= 0) {
    return bounds;
  }

  CGFloat scale = std::max(bounds.size.width / content_size.width, bounds.size.height / content_size.height);
  NSSize filled = NSMakeSize(content_size.width * scale, content_size.height * scale);
  return NSMakeRect(
    bounds.origin.x + (bounds.size.width - filled.width) * 0.5,
    bounds.origin.y + (bounds.size.height - filled.height) * 0.5,
    filled.width,
    filled.height);
}

CGFloat ClampCGFloat(CGFloat value, CGFloat minimum, CGFloat maximum)
{
  return std::min(std::max(value, minimum), maximum);
}

void SplitVerticalPanelHeights(
  CGFloat available_height,
  CGFloat gap,
  CGFloat notes_ratio,
  CGFloat &next_height,
  CGFloat &notes_height)
{
  const CGFloat panel_height = std::max<CGFloat>(1.0, available_height - gap);
  const CGFloat min_next = std::min<CGFloat>(90.0, panel_height * 0.45);
  const CGFloat min_notes = std::min<CGFloat>(80.0, std::max<CGFloat>(0.0, panel_height - min_next));
  notes_height = ClampCGFloat(panel_height * notes_ratio, min_notes, panel_height - min_next);
  next_height = panel_height - notes_height;
}

void SplitConfidenceHeights(
  CGFloat available_height,
  CGFloat gap,
  CGFloat strip_ratio,
  CGFloat &preview_height,
  CGFloat &strip_height)
{
  const CGFloat panel_height = std::max<CGFloat>(1.0, available_height - gap);
  const CGFloat min_strip = std::min<CGFloat>(112.0, panel_height * 0.30);
  const CGFloat max_strip = std::max<CGFloat>(min_strip, panel_height * 0.42);
  strip_height = ClampCGFloat(available_height * 0.22 * strip_ratio, min_strip, max_strip);
  preview_height = panel_height - strip_height;
}

NSRect PositionedPreviewRect(NSSize content_size, NSRect bounds, const PresenterRenderOptions &options)
{
  if (content_size.width <= 0 || content_size.height <= 0 ||
      bounds.size.width <= 0 || bounds.size.height <= 0) {
    return bounds;
  }

  const CGFloat fit_scale = std::min(bounds.size.width / content_size.width, bounds.size.height / content_size.height);
  const CGFloat fill_scale = std::max(bounds.size.width / content_size.width, bounds.size.height / content_size.height);
  CGFloat scale = options.preview_scale_mode == PresenterPreviewScaleMode::Fit ? fit_scale : fill_scale;
  CGFloat user_scale = ClampCGFloat(static_cast<CGFloat>(options.preview_scale_percent) / 100.0, 0.25, 3.0);
  if (options.preview_scale_mode == PresenterPreviewScaleMode::Crop) {
    user_scale = std::max<CGFloat>(1.0, user_scale);
  }
  scale *= user_scale;

  const NSSize draw_size = NSMakeSize(content_size.width * scale, content_size.height * scale);
  const CGFloat x_weight = (ClampCGFloat(static_cast<CGFloat>(options.preview_position_x), -100.0, 100.0) + 100.0) / 200.0;
  const CGFloat y_weight = (ClampCGFloat(static_cast<CGFloat>(options.preview_position_y), -100.0, 100.0) + 100.0) / 200.0;
  return NSMakeRect(
    bounds.origin.x + ((bounds.size.width - draw_size.width) * x_weight),
    bounds.origin.y + ((bounds.size.height - draw_size.height) * y_weight),
    draw_size.width,
    draw_size.height);
}

void FillRect(NSRect rect, NSColor *color)
{
  [color setFill];
  NSRectFill(rect);
}

NSColor *ColorFromRgb(uint32_t color)
{
  const CGFloat red = static_cast<CGFloat>((color >> 16) & 0xff) / 255.0;
  const CGFloat green = static_cast<CGFloat>((color >> 8) & 0xff) / 255.0;
  const CGFloat blue = static_cast<CGFloat>(color & 0xff) / 255.0;
  return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
}

void DrawLabel(NSString *text, NSRect rect, NSColor *color, NSFont *font)
{
  NSDictionary *attrs = @{
    NSForegroundColorAttributeName : color,
    NSFontAttributeName : font,
  };
  [text drawInRect:rect withAttributes:attrs];
}

NSRect PresenterBackgroundImageRect(NSImage *image, NSRect canvas, const PresenterRenderOptions &options)
{
  if (!image || image.size.width <= 0 || image.size.height <= 0) {
    return NSZeroRect;
  }

  if (options.background_image_mode == PresenterBackgroundImageMode::Fill) {
    return AspectFillRect(image.size, canvas);
  }
  if (options.background_image_mode == PresenterBackgroundImageMode::Fit) {
    return AspectFitRect(image.size, NSInsetRect(canvas, 32.0, 32.0));
  }

  const CGFloat max_width = std::max<CGFloat>(120.0, canvas.size.width * 0.24);
  const CGFloat max_height = std::max<CGFloat>(90.0, canvas.size.height * 0.20);
  const NSRect watermark_bounds = NSMakeRect(
    NSMaxX(canvas) - max_width - 28.0,
    canvas.origin.y + 24.0,
    max_width,
    max_height);
  return AspectFitRect(image.size, watermark_bounds);
}

void DrawPresenterBackgroundImage(NSRect canvas, const PresenterRenderOptions &options)
{
  if (options.background_image_path.empty()) {
    return;
  }

  NSString *path = ToNSString(options.background_image_path);
  NSImage *image = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
  if (!image) {
    return;
  }

  const CGFloat opacity =
    ClampCGFloat(static_cast<CGFloat>(options.background_image_opacity_percent) / 100.0, 0.0, 1.0);
  if (opacity <= 0.0) {
    return;
  }

  const NSRect destination = PresenterBackgroundImageRect(image, canvas, options);
  if (NSIsEmptyRect(destination)) {
    return;
  }

  [NSGraphicsContext saveGraphicsState];
  [[NSBezierPath bezierPathWithRect:canvas] addClip];
  [image drawInRect:destination
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:opacity
     respectFlipped:YES
              hints:@{ NSImageHintInterpolation : @(NSImageInterpolationHigh) }];
  [NSGraphicsContext restoreGraphicsState];
}

std::string CueTitleForSlide(const std::vector<SlideMetadata> &slides, std::size_t index)
{
  if (index < slides.size()) {
    const std::string title = TrimWhitespace(slides[index].title);
    if (!title.empty()) {
      return title;
    }
  }
  return "Slide " + std::to_string(index + 1);
}

void DrawCueList(
  const std::vector<SlideMetadata> &slides,
  const std::set<std::size_t> &checked_cues,
  std::size_t current,
  std::size_t slide_count,
  NSRect cue_box)
{
  [[NSColor colorWithCalibratedRed:0.07 green:0.10 blue:0.13 alpha:0.96] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:cue_box xRadius:8 yRadius:8] fill];
  DrawLabel(@"Cue List", NSMakeRect(cue_box.origin.x + 14, NSMaxY(cue_box) - 26, 220, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);

  const std::size_t count = std::max<std::size_t>(slide_count, slides.size());
  if (count == 0) {
    DrawLabel(@"No cues available yet", NSInsetRect(cue_box, 14, 38), [NSColor colorWithWhite:0.58 alpha:1.0], [NSFont systemFontOfSize:12]);
    return;
  }

  const std::size_t start = current > 1 ? current - 1 : 0;
  const std::size_t end = std::min<std::size_t>(count, start + 5);
  CGFloat y = NSMaxY(cue_box) - 48.0;
  for (std::size_t index = start; index < end && y > cue_box.origin.y + 8.0; ++index) {
    const bool is_current = index == current;
    const bool is_next = index == current + 1;
    const bool checked = checked_cues.find(index) != checked_cues.end();
    NSString *line = [NSString stringWithFormat:@"%s %s %02lu  %@%@",
      is_current ? ">" : " ",
      checked ? "[x]" : "[ ]",
      static_cast<unsigned long>(index + 1),
      ToNSString(CueTitleForSlide(slides, index)),
      is_next ? @"  next" : @""];
    NSDictionary *attrs = @{
      NSForegroundColorAttributeName : is_current ? [NSColor colorWithCalibratedRed:0.33 green:0.89 blue:0.67 alpha:1.0] : [NSColor colorWithWhite:0.82 alpha:1.0],
      NSFontAttributeName : [NSFont monospacedSystemFontOfSize:12 weight:(is_current ? NSFontWeightSemibold : NSFontWeightRegular)],
    };
    [line drawInRect:NSMakeRect(cue_box.origin.x + 14.0, y, cue_box.size.width - 28.0, 18.0)
      withAttributes:attrs];
    y -= 20.0;
  }
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

void DrawPagePreview(PDFDocument *document, std::size_t index, NSRect rect, const PresenterRenderOptions &options)
{
  FillRect(rect, [NSColor blackColor]);
  if (!document || index >= static_cast<std::size_t>(document.pageCount)) {
    return;
  }

  PDFPage *page = [document pageAtIndex:static_cast<NSInteger>(index)];
  if (!page) {
    return;
  }

  const NSRect page_bounds = [page boundsForBox:kPDFDisplayBoxMediaBox];
  const NSRect destination = PositionedPreviewRect(page_bounds.size, rect, options);
  NSImage *thumbnail = [page thumbnailOfSize:destination.size forBox:kPDFDisplayBoxMediaBox];
  if (!thumbnail) {
    return;
  }

  [NSGraphicsContext saveGraphicsState];
  [[NSBezierPath bezierPathWithRect:rect] addClip];
  [thumbnail drawInRect:destination];
  [NSGraphicsContext restoreGraphicsState];
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

long long ElapsedMs(Clock::time_point start)
{
  return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - start).count();
}

}  // namespace

struct PresentationDocument::Impl {
  explicit Impl(std::string input_path)
    : path(std::move(input_path)),
      name(fs::path(path).filename().string()),
      live_queue(dispatch_queue_create("com.srdjankotarlic.pptbridge.live", DISPATCH_QUEUE_SERIAL))
  {
    dispatch_queue_set_specific(live_queue, LiveQueueSpecificKey(), (__bridge void *)live_queue, nullptr);
  }

  mutable std::mutex mutex;
  std::string path;
  std::string name;
  std::string cache_dir;
  std::string pdf_path;
  std::string error;
  std::vector<SlideMetadata> slides;
  std::set<std::size_t> checked_cues;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  bool loading = false;
  bool loaded = false;
  bool load_requested = true;
  bool presenter_assets_wanted = false;
  bool live_powerpoint_enabled = false;
  bool live_powerpoint_auto_start = false;
  bool live_start_requested = false;
  bool live_ready = false;
  bool live_sync_in_flight = false;
  bool black = false;
  bool current_media_triggered = false;
  std::size_t current = 0;
  std::size_t live_slide_count = 0;
  std::string live_window_title;
  std::string live_presentation_path;
  std::string live_error;
  Clock::time_point live_last_sync = Clock::time_point::min();
  uint64_t version = 1;
  Clock::time_point started_at = Clock::now();
  PDFDocument *__strong pdf_document = nil;
  dispatch_queue_t live_queue = nil;
  mutable std::mutex render_mutex;
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
  if (enabled && impl_->live_powerpoint_auto_start && !impl_->live_ready) {
    impl_->live_start_requested = true;
  } else if (!enabled) {
    impl_->live_start_requested = false;
    impl_->live_ready = false;
    impl_->live_window_title.clear();
    impl_->live_presentation_path.clear();
    impl_->live_slide_count = 0;
    impl_->live_sync_in_flight = false;
  }
  impl_->load_requested = true;
  impl_->version += 1;
}

void PresentationDocument::SetLivePowerPointAutoStart(bool enabled)
{
  bool should_start = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const auto extension_lower = ToLowerCopy(fs::path(impl_->path).extension().string());
    if (extension_lower == ".pdf") {
      enabled = false;
    }
    if (impl_->live_powerpoint_auto_start == enabled) {
      return;
    }

    impl_->live_powerpoint_auto_start = enabled;
    if (enabled && impl_->live_powerpoint_enabled && !impl_->live_ready) {
      impl_->live_start_requested = true;
      impl_->load_requested = true;
      should_start = true;
    } else if (!enabled && !impl_->live_ready) {
      impl_->live_start_requested = false;
    }
    impl_->version += 1;
  }

  if (should_start) {
    StartLoadIfNeeded(false);
  }
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

void PresentationDocument::StartLivePowerPointAsync()
{
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const auto extension_lower = ToLowerCopy(fs::path(impl_->path).extension().string());
    if (extension_lower == ".pdf") {
      impl_->live_powerpoint_enabled = false;
      impl_->live_start_requested = false;
      return;
    }
    impl_->live_powerpoint_enabled = true;
    impl_->live_start_requested = true;
    impl_->live_ready = false;
    impl_->live_sync_in_flight = false;
    impl_->live_window_title.clear();
    impl_->live_presentation_path.clear();
    impl_->live_slide_count = 0;
    impl_->live_last_sync = Clock::time_point::min();
    impl_->live_error.clear();
    impl_->black = false;
    impl_->current_media_triggered = false;
    impl_->load_requested = true;
    impl_->version += 1;
  }

  StartLoadIfNeeded(false);
}

void PresentationDocument::StopLivePowerPoint()
{
  if (dispatch_get_specific(LiveQueueSpecificKey()) == (__bridge void *)impl_->live_queue) {
    StopLivePowerPointOnLiveQueue();
    return;
  }

  dispatch_sync(impl_->live_queue, ^{
    StopLivePowerPointOnLiveQueue();
  });
}

void PresentationDocument::StopLivePowerPointOnLiveQueue()
{
  std::string cache_dir;
  std::string window_title;
  std::string presentation_path;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    cache_dir = impl_->cache_dir;
    window_title = impl_->live_window_title;
    presentation_path = impl_->live_presentation_path;
  }

  std::string stop_error;
  const bool stopped = StopPowerPointLiveSession(cache_dir, presentation_path, window_title, stop_error);
  if (!window_title.empty() || !presentation_path.empty()) {
    if (stopped) {
      blog(LOG_INFO,
        "[PPTBridge] PowerPoint live mode stopped (%s)",
        !window_title.empty() ? window_title.c_str() : presentation_path.c_str());
    } else {
      blog(LOG_WARNING,
        "[PPTBridge] PowerPoint live mode stop failed (%s): %s",
        !window_title.empty() ? window_title.c_str() : presentation_path.c_str(),
        stop_error.c_str());
    }
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->live_start_requested = false;
  impl_->live_ready = false;
  impl_->live_sync_in_flight = false;
  impl_->live_window_title.clear();
  impl_->live_presentation_path.clear();
  impl_->live_slide_count = 0;
  impl_->live_error = stopped ? std::string() : stop_error;
  impl_->version += 1;
}

void PresentationDocument::StopLivePowerPointAsync()
{
  auto self = shared_from_this();
  dispatch_async(impl_->live_queue, ^{
    self->StopLivePowerPointOnLiveQueue();
  });
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
  std::string cache_dir;
  std::string presentation_path;
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

    cache_dir = impl_->cache_dir;
    presentation_path = impl_->live_presentation_path;
    impl_->live_sync_in_flight = true;
  }

  auto self = shared_from_this();
  dispatch_async(impl_->live_queue, ^{
    LivePowerPointSnapshot snapshot;
    std::string error;
    const bool ok = QueryPowerPointLiveState(cache_dir, presentation_path, snapshot, error);

    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    self->impl_->live_sync_in_flight = false;
    self->impl_->live_last_sync = Clock::now();
    if (!self->impl_->live_powerpoint_enabled) {
      return;
    }

    if (!ok) {
      self->impl_->live_ready = false;
      self->impl_->live_window_title.clear();
      self->impl_->live_presentation_path.clear();
      self->impl_->live_slide_count = 0;
      self->impl_->live_error = LiveRecoveryErrorMessage(error);
      self->impl_->version += 1;
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
    if (!snapshot.presentation_path.empty()) {
      self->impl_->live_presentation_path = snapshot.presentation_path;
    }
    self->impl_->live_slide_count = snapshot.slide_count;
    self->impl_->current = snapshot.current_index;
    if (changed) {
      self->impl_->version += 1;
    }
  });
}

void PresentationDocument::RunLivePowerPointCommandAsync(std::string command_line, bool clear_black)
{
  std::string cache_dir;
  std::string presentation_path;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->live_powerpoint_enabled || !impl_->live_ready) {
      return;
    }
    cache_dir = impl_->cache_dir;
    presentation_path = impl_->live_presentation_path;
  }

  auto self = shared_from_this();
  dispatch_async(impl_->live_queue, ^{
    LivePowerPointSnapshot snapshot;
    std::string error;
    const bool ok = RunPowerPointLiveCommand(cache_dir, presentation_path, command_line, snapshot, error);

    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    if (!self->impl_->live_powerpoint_enabled) {
      return;
    }

    if (ok) {
      self->impl_->current = snapshot.current_index;
      self->impl_->live_slide_count = snapshot.slide_count;
      self->impl_->live_window_title = snapshot.window_title;
      if (!snapshot.presentation_path.empty()) {
        self->impl_->live_presentation_path = snapshot.presentation_path;
      }
      self->impl_->live_error.clear();
      if (clear_black) {
        self->impl_->black = false;
      }
    } else {
      self->impl_->live_ready = false;
      self->impl_->live_sync_in_flight = false;
      self->impl_->live_window_title.clear();
      self->impl_->live_presentation_path.clear();
      self->impl_->live_slide_count = 0;
      self->impl_->live_error = LiveRecoveryErrorMessage(error);
      if (clear_black) {
        self->impl_->black = false;
      }
    }
    self->impl_->version += 1;
  });
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
    const auto load_started = Clock::now();
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
        impl_->live_presentation_path.clear();
        impl_->live_slide_count = 0;
        impl_->live_sync_in_flight = false;
      }
    }

    bool live_enabled = false;
    bool live_auto_start = false;
    bool live_start_requested = false;
    bool already_live_ready = false;
    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      live_enabled = impl_->live_powerpoint_enabled;
      live_auto_start = impl_->live_powerpoint_auto_start;
      live_start_requested = impl_->live_start_requested;
      already_live_ready = impl_->live_ready;
    }

    bool live_started_now = false;
    if (live_enabled && live_start_requested && !already_live_ready) {
      LivePowerPointSnapshot live_snapshot;
      std::string live_error;
      const auto live_start_started = Clock::now();
      if (StartPowerPointLiveSession(impl_->path, cache_dir, live_snapshot, live_error)) {
        live_started_now = true;
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->cache_dir = cache_dir;
        impl_->live_ready = true;
        impl_->live_error.clear();
        impl_->live_window_title = live_snapshot.window_title;
        impl_->live_presentation_path = !live_snapshot.presentation_path.empty()
          ? live_snapshot.presentation_path
          : StagedPowerPointLivePath(impl_->path, fs::path(cache_dir) / "powerpoint-live").string();
        impl_->live_slide_count = live_snapshot.slide_count;
        impl_->current = live_snapshot.current_index;
        impl_->black = false;
        impl_->current_media_triggered = false;
        impl_->started_at = Clock::now();
        impl_->version += 1;
        blog(LOG_INFO,
          "[PPTBridge] PowerPoint live mode started for '%s' (%s) in %lld ms",
          impl_->path.c_str(),
          live_snapshot.window_title.c_str(),
          ElapsedMs(live_start_started));
      } else {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->live_ready = false;
        impl_->live_error = live_error;
        impl_->live_window_title.clear();
        impl_->live_presentation_path.clear();
        impl_->live_slide_count = 0;
        impl_->version += 1;
        blog(LOG_WARNING,
          "[PPTBridge] Live mode failed for '%s' after %lld ms: %s",
          impl_->path.c_str(),
          ElapsedMs(live_start_started),
          live_error.c_str());
      }
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
    } else {
      const auto convert_started = Clock::now();
      if (!ConvertPptxToPdf(
            impl_->path,
            cache_dir,
            pdf_path,
            error,
            !live_enabled || live_auto_start || live_start_requested || already_live_ready || live_started_now)) {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->loading = false;
        impl_->loaded = false;
        impl_->error = error;
        impl_->version += 1;
        blog(LOG_WARNING, "[PPTBridge] Failed to load '%s': %s", impl_->path.c_str(), error.c_str());
        return;
      }
      blog(LOG_INFO,
        "[PPTBridge] Prepared static PDF for '%s' in %lld ms",
        impl_->path.c_str(),
        ElapsedMs(convert_started));
    }

    const auto pdf_open_started = Clock::now();
    PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:ToNSString(pdf_path)]];
    const auto pdf_open_ms = ElapsedMs(pdf_open_started);
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
    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->cache_dir = cache_dir;
      impl_->pdf_path = pdf_path;
      impl_->slides = PlaceholderDeckMetadata(slide_count, is_pdf_source);
      impl_->media_by_slide.clear();
      impl_->media_by_slide.resize(slide_count);
      impl_->pdf_document = document;
      impl_->loaded = true;
      impl_->loading = true;
      impl_->current_media_triggered = false;
      if (!impl_->live_ready) {
        impl_->black = false;
        impl_->current = 0;
        impl_->started_at = Clock::now();
      }
      impl_->error.clear();
      impl_->version += 1;
    }
    blog(LOG_INFO,
      "[PPTBridge] Opened static preview for '%s' with %ld slide(s) in %lld ms (PDF open %lld ms); preparing notes/media",
      impl_->path.c_str(),
      static_cast<long>(document.pageCount),
      ElapsedMs(load_started),
      pdf_open_ms);

    // pptx-only metadata extractors read inside the .pptx zip; skip them
    // entirely when the source is a standalone .pdf so we don't spawn
    // unzip processes against a file that is not a zip archive.
    const auto metadata_started = Clock::now();
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
    const auto metadata_ms = ElapsedMs(metadata_started);

    bool restart_for_queued_request = false;
    {
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
      restart_for_queued_request = impl_->load_requested;
      impl_->version += 1;
    }
    blog(LOG_INFO,
      "[PPTBridge] Loaded '%s' with %ld slide(s) in %lld ms (PDF open %lld ms, metadata/media %lld ms)",
      impl_->path.c_str(),
      static_cast<long>(document.pageCount),
      ElapsedMs(load_started),
      pdf_open_ms,
      metadata_ms);
    if (restart_for_queued_request) {
      blog(LOG_INFO,
        "[PPTBridge] Continuing queued load/start request for '%s' after notes/media preparation",
        impl_->path.c_str());
      StartLoadIfNeeded(false);
    }
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
    RunLivePowerPointCommandAsync(
      R"(set targetWindow to slide show window of targetPresentation
		set targetView to slideshow view of targetWindow
		set currentLiveSlide to slide index of slide of targetView
		set targetSlideCount to count of slides of targetPresentation
		if currentLiveSlide < targetSlideCount then
			go to next slide (slideshow view of targetWindow)
		end if)",
      true);
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
    RunLivePowerPointCommandAsync(
      R"(go to previous slide (slideshow view of slide show window of targetPresentation))",
      true);
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
    RunLivePowerPointCommandAsync(
      R"(go to first slide (slideshow view of slide show window of targetPresentation))",
      true);
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
    RunLivePowerPointCommandAsync(
      R"(go to last slide (slideshow view of slide show window of targetPresentation))",
      true);
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

PresentationStatus PresentationDocument::SnapshotStatus() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);

  PresentationStatus status;
  status.deck_name = impl_->name;
  status.deck_path = impl_->path;
  status.error = !impl_->live_error.empty() ? impl_->live_error : impl_->error;
  status.live_enabled = impl_->live_powerpoint_enabled;
  status.live_ready = impl_->live_powerpoint_enabled && impl_->live_ready;
  status.loading = impl_->loading;
  status.loaded = impl_->loaded;
  status.black_screen = impl_->black;
  status.total_slides = impl_->live_powerpoint_enabled && impl_->live_slide_count > 0
    ? impl_->live_slide_count
    : (impl_->loaded && impl_->pdf_document ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : impl_->slides.size());
  status.current_index = status.total_slides > 0 ? std::min(impl_->current, status.total_slides - 1) : 0;
  status.current_slide = status.total_slides > 0 ? status.current_index + 1 : 0;
  status.current_title = status.current_slide > 0 ? CueTitleForSlide(impl_->slides, status.current_index) : "";
  if (status.current_index + 1 < status.total_slides) {
    status.next_title = CueTitleForSlide(impl_->slides, status.current_index + 1);
  }
  status.timer_seconds = static_cast<uint64_t>(
    std::chrono::duration_cast<std::chrono::seconds>(Clock::now() - impl_->started_at).count());

  const std::size_t cue_count = std::max<std::size_t>(status.total_slides, impl_->slides.size());
  status.cues.reserve(cue_count);
  for (std::size_t index = 0; index < cue_count; ++index) {
    const bool checked = impl_->checked_cues.find(index) != impl_->checked_cues.end();
    CueListItem item;
    item.index = index;
    item.number = index + 1;
    item.title = CueTitleForSlide(impl_->slides, index);
    item.current = status.current_slide > 0 && index == status.current_index;
    item.next = status.current_slide > 0 && index == status.current_index + 1 && index < cue_count;
    item.checked = checked;
    if (item.current) {
      status.current_cue_checked = checked;
    }
    if (item.next) {
      status.next_cue_checked = checked;
    }
    if (checked) {
      status.checked_count += 1;
    }
    status.cues.push_back(std::move(item));
  }

  return status;
}

bool PresentationDocument::SetCueChecked(std::size_t index, bool checked)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  const std::size_t cue_count = std::max<std::size_t>(
    impl_->slides.size(),
    impl_->live_powerpoint_enabled && impl_->live_slide_count > 0
      ? impl_->live_slide_count
      : (impl_->loaded && impl_->pdf_document ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : 0));
  if (index >= cue_count) {
    return false;
  }

  const bool was_checked = impl_->checked_cues.find(index) != impl_->checked_cues.end();
  if (checked == was_checked) {
    return true;
  }

  if (checked) {
    impl_->checked_cues.insert(index);
  } else {
    impl_->checked_cues.erase(index);
  }
  impl_->version += 1;
  return true;
}

bool PresentationDocument::ToggleCueChecked(std::size_t index)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  const std::size_t cue_count = std::max<std::size_t>(
    impl_->slides.size(),
    impl_->live_powerpoint_enabled && impl_->live_slide_count > 0
      ? impl_->live_slide_count
      : (impl_->loaded && impl_->pdf_document ? static_cast<std::size_t>(impl_->pdf_document.pageCount) : 0));
  if (index >= cue_count) {
    return false;
  }

  auto found = impl_->checked_cues.find(index);
  if (found == impl_->checked_cues.end()) {
    impl_->checked_cues.insert(index);
  } else {
    impl_->checked_cues.erase(found);
  }
  impl_->version += 1;
  return true;
}

void PresentationDocument::ClearCueChecks()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->checked_cues.empty()) {
    return;
  }
  impl_->checked_cues.clear();
  impl_->version += 1;
}

bool PresentationDocument::ExportCueList(std::string &out_path, std::string &out_error) const
{
  std::vector<SlideMetadata> slides;
  std::set<std::size_t> checked_cues;
  std::string deck_path;
  std::string deck_name;
  std::size_t current = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->loaded || impl_->slides.empty()) {
      out_error = impl_->loading ? "presentation is still loading" : "no loaded slides to export";
      return false;
    }
    slides = impl_->slides;
    checked_cues = impl_->checked_cues;
    deck_path = impl_->path;
    deck_name = impl_->name;
    current = impl_->current;
  }

  fs::path output = fs::path(deck_path);
  output.replace_extension(".pptbridge-cues.txt");

  std::ofstream file(output, std::ios::out | std::ios::trunc);
  if (!file) {
    out_error = "could not create cue list at " + output.string();
    return false;
  }

  file << "PPTBridge SK Cue List\n";
  file << "Deck: " << deck_name << "\n\n";
  for (std::size_t index = 0; index < slides.size(); ++index) {
    const std::string title = CueTitleForSlide(slides, index);
    file << (checked_cues.find(index) != checked_cues.end() ? "[x] " : "[ ] ");
    if (index == current) {
      file << "> ";
    } else if (index == current + 1) {
      file << "next ";
    } else {
      file << "  ";
    }
    file << (index + 1) << ". " << title << "\n";
    const std::string notes = TrimWhitespace(slides[index].notes);
    if (!notes.empty()) {
      file << "   Notes: " << notes << "\n";
    }
  }

  out_path = output.string();
  out_error.clear();
  return true;
}

bool PresentationDocument::RenderSlideBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride) const
{
  @autoreleasepool {
    std::lock_guard<std::mutex> render_lock(impl_->render_mutex);
    PDFDocument *document = nil;
    bool loading = false;
    bool loaded = false;
	    bool live_enabled = false;
	    bool live_ready = false;
	    bool live_waiting_for_manual_start = false;
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
	      live_waiting_for_manual_start =
	        impl_->live_powerpoint_enabled &&
	        !impl_->live_powerpoint_auto_start &&
	        !impl_->live_start_requested &&
	        !impl_->live_ready &&
	        !impl_->path.empty();
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
    } else if (live_waiting_for_manual_start) {
      DrawCenteredMessage(@"PPTBridge SK", @"PowerPoint live mode is manual. Click Start / Restart PowerPoint Live Mode in the highlighted source-property group.", canvas);
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
  uint32_t &out_stride,
  const PresenterRenderOptions &options) const
{
  @autoreleasepool {
    std::lock_guard<std::mutex> render_lock(impl_->render_mutex);
    PDFDocument *document = nil;
    std::vector<SlideMetadata> slides;
    std::set<std::size_t> checked_cues;
    bool loading = false;
    bool loaded = false;
    bool live_enabled = false;
    bool live_ready = false;
    bool live_waiting_for_manual_start = false;
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
      checked_cues = impl_->checked_cues;
      loading = impl_->loading;
      loaded = impl_->loaded;
      live_enabled = impl_->live_powerpoint_enabled;
      live_ready = impl_->live_ready;
      live_waiting_for_manual_start =
        impl_->live_powerpoint_enabled &&
        !impl_->live_powerpoint_auto_start &&
        !impl_->live_start_requested &&
        !impl_->live_ready &&
        !impl_->path.empty();
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
    FillRect(canvas, ColorFromRgb(options.background_color));
    DrawPresenterBackgroundImage(canvas, options);

    const bool confidence_layout = options.layout == PresenterLayoutPreset::ConfidenceMonitor;
    const bool compact_layout = options.layout == PresenterLayoutPreset::Compact;
    const CGFloat top_bar_height = confidence_layout ? 0.0 : (compact_layout ? 44.0 : 56.0);

    if (top_bar_height > 0.0) {
      NSRect top_bar = NSMakeRect(0, height - top_bar_height, width, top_bar_height);
      FillRect(top_bar, [NSColor colorWithCalibratedRed:0.07 green:0.10 blue:0.13 alpha:1.0]);
      DrawLabel(
        @"PPTBridge SK Presenter",
        NSMakeRect(24, height - (compact_layout ? 32 : 40), 320, 24),
        [NSColor whiteColor],
        [NSFont boldSystemFontOfSize:(compact_layout ? 16 : 20)]);
      if (!compact_layout) {
        DrawLabel(
          ToNSString(name),
          NSMakeRect(24, height - 62, width - 320, 18),
          [NSColor colorWithWhite:0.65 alpha:1.0],
          [NSFont systemFontOfSize:12 weight:NSFontWeightRegular]);
      }
      DrawLabel(
        ToNSString(FormatTimer(timer_seconds)),
        NSMakeRect(width - 120, height - (compact_layout ? 32 : 40), 96, 24),
        [NSColor whiteColor],
        [NSFont monospacedDigitSystemFontOfSize:(compact_layout ? 16 : 20) weight:NSFontWeightSemibold]);
    }

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
      } else if (live_waiting_for_manual_start) {
        subtitle = @"PowerPoint live mode is manual. Click Start / Restart PowerPoint Live Mode in the highlighted source-property group.";
      } else if (live_enabled && loading) {
        subtitle = @"Starting PowerPoint live mode and loading presenter notes…";
      } else if (live_enabled && !live_error.empty()) {
        subtitle = ToNSString(live_error);
      } else if (loading) {
        subtitle = @"Loading presentation…";
      } else {
        subtitle = error.empty() ? @"Choose a .pptx in source properties" : ToNSString(error);
      }
      DrawCenteredMessage(@"PPTBridge SK", subtitle, NSMakeRect(0, 0, width, height - top_bar_height));
      [NSGraphicsContext restoreGraphicsState];
      out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
      CopyBitmapToBGRA(bitmap, height, out_pixels);
      return true;
    }

    const std::size_t pdf_slide_count = document ? static_cast<std::size_t>(document.pageCount) : 0;
    if (pdf_slide_count == 0) {
      DrawCenteredMessage(@"PPTBridge SK", @"Presenter thumbnails are not available for this deck yet.", NSMakeRect(0, 0, width, height - top_bar_height));
      [NSGraphicsContext restoreGraphicsState];
      out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
      CopyBitmapToBGRA(bitmap, height, out_pixels);
      return true;
    }

    current = std::min(current, pdf_slide_count - 1);
    const std::size_t shown_slide_count = slide_count > 0 ? slide_count : pdf_slide_count;

    const CGFloat margin = compact_layout ? 10.0 : 18.0;
    const CGFloat gap = compact_layout ? 10.0 : 16.0;
    const CGFloat footer_height = compact_layout ? 42.0 : 54.0;
    const CGFloat content_bottom = margin + footer_height;
    const CGFloat content_top = height - top_bar_height - margin;
    const CGFloat content_height = std::max<CGFloat>(1.0, content_top - content_bottom);
    const CGFloat content_width = std::max<CGFloat>(120.0, width - (margin * 2.0));

    CGFloat right_ratio = 0.28;
    CGFloat notes_base_ratio = 0.62;
    if (options.layout == PresenterLayoutPreset::LargePreview) {
      right_ratio = 0.22;
      notes_base_ratio = 0.56;
    } else if (options.layout == PresenterLayoutPreset::LargeNotes) {
      right_ratio = 0.36;
      notes_base_ratio = 0.76;
    } else if (compact_layout) {
      right_ratio = 0.24;
      notes_base_ratio = 0.58;
    }

    NSRect left = NSZeroRect;
    NSRect right = NSZeroRect;
    NSRect next_box = NSZeroRect;
    NSRect notes_box = NSZeroRect;
    NSRect cue_box = NSZeroRect;

    if (confidence_layout) {
      const CGFloat strip_ratio =
        ClampCGFloat(static_cast<CGFloat>(options.notes_area_percent) / 100.0, 0.60, 1.80);
      CGFloat preview_height = 0.0;
      CGFloat strip_height = 0.0;
      SplitConfidenceHeights(content_height, gap, strip_ratio, preview_height, strip_height);
      left = NSMakeRect(
        margin,
        content_bottom + strip_height + gap,
        content_width,
        preview_height);
      right = NSMakeRect(margin, content_bottom, content_width, strip_height);
      const CGFloat next_width = ClampCGFloat(right.size.width * 0.28, 120.0, right.size.width * 0.42);
      next_box = NSMakeRect(right.origin.x, right.origin.y, next_width, right.size.height);
      notes_box = NSMakeRect(
        NSMaxX(next_box) + gap,
        right.origin.y,
        std::max<CGFloat>(80.0, right.size.width - next_box.size.width - gap),
        right.size.height);
    } else {
      const CGFloat minimum_right = compact_layout ? 240.0 : 300.0;
      const CGFloat maximum_right = std::max<CGFloat>(180.0, content_width - 220.0 - gap);
      const CGFloat right_panel_scale =
        ClampCGFloat(static_cast<CGFloat>(options.side_panel_width_percent) / 100.0, 0.50, 2.20);
      const CGFloat right_width = ClampCGFloat(width * right_ratio * right_panel_scale, minimum_right, maximum_right);
      left = NSMakeRect(margin, content_bottom, content_width - right_width - gap, content_height);
      right = NSMakeRect(NSMaxX(left) + gap, content_bottom, right_width, content_height);

      const CGFloat notes_multiplier =
        ClampCGFloat(static_cast<CGFloat>(options.notes_area_percent) / 100.0, 0.60, 1.80);
      CGFloat notes_ratio = ClampCGFloat(notes_base_ratio * notes_multiplier, 0.38, 0.86);
      CGFloat next_height = 0.0;
      CGFloat notes_height = 0.0;
      SplitVerticalPanelHeights(right.size.height, gap, notes_ratio, next_height, notes_height);
      next_box = NSMakeRect(right.origin.x, NSMaxY(right) - next_height, right.size.width, next_height);
      notes_box = NSMakeRect(right.origin.x, right.origin.y, right.size.width, notes_height);
    }

    if (options.show_cue_list && notes_box.size.height >= 150.0) {
      const CGFloat cue_height = ClampCGFloat(notes_box.size.height * 0.28, 92.0, 172.0);
      cue_box = NSMakeRect(notes_box.origin.x, notes_box.origin.y, notes_box.size.width, cue_height);
      notes_box = NSMakeRect(
        notes_box.origin.x,
        NSMaxY(cue_box) + gap,
        notes_box.size.width,
        std::max<CGFloat>(80.0, notes_box.size.height - cue_height - gap));
    }

    DrawPagePreview(document, current, left, options);

    NSRect slide_count_rect = NSMakeRect(left.origin.x, compact_layout ? 10 : 18, 210, 30);
    DrawLabel(
      [NSString stringWithFormat:@"Slide %lu / %lu",
        static_cast<unsigned long>(current + 1),
        static_cast<unsigned long>(shown_slide_count)],
      slide_count_rect,
      [NSColor colorWithWhite:0.75 alpha:1.0],
      [NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightMedium]);

    [[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.15 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:next_box xRadius:8 yRadius:8] fill];
    DrawLabel(@"Next Slide", NSMakeRect(next_box.origin.x + 14, NSMaxY(next_box) - 26, 200, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);
    if (current + 1 < pdf_slide_count) {
      NSRect next_preview_rect = NSMakeRect(
        next_box.origin.x + 12.0,
        next_box.origin.y + 12.0,
        std::max<CGFloat>(1.0, next_box.size.width - 24.0),
        std::max<CGFloat>(1.0, next_box.size.height - 48.0));
      DrawPagePreview(document, current + 1, next_preview_rect, options);
    } else {
      DrawCenteredMessage(@"End", @"No next slide", next_box);
    }

    [[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.15 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:notes_box xRadius:8 yRadius:8] fill];
    DrawLabel(@"Presenter Notes", NSMakeRect(notes_box.origin.x + 14, NSMaxY(notes_box) - 26, 240, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);

    std::string notes;
    if (current < slides.size()) {
      notes = slides[current].notes;
    }
    NSString *notes_text = notes.empty() ? @"No presenter notes found in the PPTX notes page for this slide." : ToNSString(notes);
    const CGFloat notes_zoom =
      ClampCGFloat(static_cast<CGFloat>(options.notes_zoom_percent) / 100.0, 0.50, 2.00);
    const CGFloat notes_font_size =
      ClampCGFloat(static_cast<CGFloat>(options.notes_font_size) * notes_zoom, 8.0, 64.0);
    NSDictionary *notes_attrs = @{
      NSForegroundColorAttributeName : notes.empty() ? [NSColor colorWithWhite:0.55 alpha:1.0] : [NSColor colorWithWhite:0.95 alpha:1.0],
      NSFontAttributeName : [NSFont monospacedSystemFontOfSize:notes_font_size weight:NSFontWeightRegular],
    };
    NSRect notes_text_rect = NSMakeRect(
      notes_box.origin.x + 14.0,
      notes_box.origin.y + 14.0,
      std::max<CGFloat>(1.0, notes_box.size.width - 28.0),
      std::max<CGFloat>(1.0, notes_box.size.height - 50.0));
    const CGFloat notes_offset_y =
      (ClampCGFloat(static_cast<CGFloat>(options.notes_position_y), -100.0, 100.0) / 100.0) *
      notes_text_rect.size.height *
      0.35;
    notes_text_rect.origin.y -= notes_offset_y;
    [notes_text drawInRect:notes_text_rect withAttributes:notes_attrs];

    if (!NSIsEmptyRect(cue_box)) {
      DrawCueList(slides, checked_cues, current, shown_slide_count, cue_box);
    }

    [NSGraphicsContext restoreGraphicsState];

    out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
    CopyBitmapToBGRA(bitmap, height, out_pixels);
    return true;
  }
}

}  // namespace pptbridge
