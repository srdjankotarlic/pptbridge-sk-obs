#import "presentation_document.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

#include <obs-module.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <sstream>
#include <thread>

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
}

std::string FindPowerPointBundle()
{
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
}

std::string CacheDirectoryForDeck(const std::string &pptx_path)
{
  std::stringstream stream;
  stream << std::hash<std::string>{}(pptx_path);
  auto hash = stream.str();
  auto base = ToStdString(NSTemporaryDirectory());
  auto dir = fs::path(base) / "pptbridge-native" / hash;
  fs::create_directories(dir);
  return dir.string();
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
  fs::remove_all(work_dir);
  fs::create_directories(work_dir);

  auto output_pdf = work_dir / "deck.pdf";
  std::error_code remove_error;
  fs::remove(output_pdf, remove_error);

  std::string std_out;
  std::string std_err;
  int exit_code = 0;
  const bool launched = RunAppleScriptFile(
    cache_dir,
    "pptbridge_powerpoint_save_as.applescript",
    PowerPointAppleScriptSaveAsSource(),
    { pptx_path, output_pdf.string() },
    std_out,
    std_err,
    exit_code);

  if (launched && exit_code == 0 && fs::exists(output_pdf)) {
    auto final_pdf = fs::path(cache_dir) / "deck.pdf";
    fs::copy_file(output_pdf, final_pdf, fs::copy_options::overwrite_existing);
    out_pdf_path = final_pdf.string();
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

  std::string libreoffice_error;
  if (ConvertPptxToPdfWithLibreOffice(pptx_path, cache_dir, out_pdf_path, libreoffice_error)) {
    return true;
  }

  blog(
    LOG_WARNING,
    "[PPTBridge] LibreOffice export failed for '%s'; trying PowerPoint fallback: %s",
    pptx_path.c_str(),
    libreoffice_error.c_str());

  std::string powerpoint_error;
  if (ConvertPptxToPdfWithPowerPoint(pptx_path, cache_dir, out_pdf_path, powerpoint_error)) {
    return true;
  }

  out_error = "LibreOffice export failed: " + libreoffice_error;
  if (!powerpoint_error.empty()) {
    out_error += " PowerPoint fallback failed: " + powerpoint_error;
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
        bool is_body = false;
        for (NSXMLNode *placeholder_node in placeholders) {
          if (![placeholder_node isKindOfClass:[NSXMLElement class]]) {
            continue;
          }
          NSString *type = [(NSXMLElement *)placeholder_node attributeForName:@"type"].stringValue ?: @"";
          if ([type isEqualToString:@"body"]) {
            is_body = true;
            break;
          }
        }
        if (!is_body) {
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
      meta.notes = ToStdString(JoinLines(lines));
    }
  }

  return meta;
}

std::vector<SlideMetadata> ExtractDeckMetadata(const std::string &pptx_path, std::size_t slide_count)
{
  std::vector<SlideMetadata> result(slide_count);
  auto slide_entries = ListSlideEntries(pptx_path);
  for (std::size_t index = 0; index < slide_entries.size() && index < slide_count; ++index) {
    auto number = static_cast<int>(index + 1);
    auto notes_entry = "ppt/notesSlides/notesSlide" + std::to_string(number) + ".xml";
    result[index] = ExtractMetadataForSlide(pptx_path, slide_entries[index], notes_entry);
  }
  return result;
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
  bool loading = false;
  bool loaded = false;
  bool load_requested = true;
  bool black = false;
  std::size_t current = 0;
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

void PresentationDocument::EnsureLoadingAsync()
{
  StartLoadIfNeeded(false);
}

void PresentationDocument::ReloadAsync()
{
  StartLoadIfNeeded(true);
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

    if (!ConvertPptxToPdf(impl_->path, cache_dir, pdf_path, error)) {
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

    auto metadata = ExtractDeckMetadata(impl_->path, static_cast<std::size_t>(document.pageCount));

    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->cache_dir = cache_dir;
    impl_->pdf_path = pdf_path;
    impl_->slides = std::move(metadata);
    impl_->pdf_document = document;
    impl_->loaded = true;
    impl_->loading = false;
    impl_->black = false;
    impl_->current = 0;
    impl_->started_at = Clock::now();
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
  return impl_->error;
}

std::size_t PresentationDocument::SlideCount() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
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
  return impl_->loaded && impl_->current + 1 < static_cast<std::size_t>(impl_->pdf_document.pageCount);
}

bool PresentationDocument::HasPrevious() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->loaded && impl_->current > 0;
}

bool PresentationDocument::IsBlackScreen() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->black;
}

void PresentationDocument::Next()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || impl_->current + 1 >= static_cast<std::size_t>(impl_->pdf_document.pageCount)) {
    return;
  }
  impl_->current += 1;
  impl_->version += 1;
}

void PresentationDocument::Previous()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || impl_->current == 0) {
    return;
  }
  impl_->current -= 1;
  impl_->version += 1;
}

void PresentationDocument::First()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded) {
    return;
  }
  impl_->current = 0;
  impl_->version += 1;
}

void PresentationDocument::Last()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || impl_->pdf_document.pageCount <= 0) {
    return;
  }
  impl_->current = static_cast<std::size_t>(impl_->pdf_document.pageCount - 1);
  impl_->version += 1;
}

void PresentationDocument::GoTo(std::size_t index)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->loaded || index >= static_cast<std::size_t>(impl_->pdf_document.pageCount)) {
    return;
  }
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
    bool black = false;
    std::string error;
    std::size_t current = 0;

    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      document = impl_->pdf_document;
      loading = impl_->loading;
      loaded = impl_->loaded;
      black = impl_->black;
      error = impl_->error;
      current = impl_->current;
    }

    NSBitmapImageRep *bitmap = CreateBitmap(width, height);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];

    NSRect canvas = NSMakeRect(0, 0, width, height);
    FillRect(canvas, [NSColor blackColor]);

    if (loaded && !black) {
      DrawPageThumbnail(document, current, canvas);
    } else if (loading) {
      DrawCenteredMessage(@"PPTBridge SK", @"Loading presentation…", canvas);
    } else if (!error.empty()) {
      DrawCenteredMessage(@"PPTBridge SK", ToNSString(error), canvas);
    } else {
      DrawCenteredMessage(@"PPTBridge SK", @"Choose a .pptx in source properties", canvas);
    }

    [NSGraphicsContext restoreGraphicsState];

    out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
    out_pixels.assign(bitmap.bitmapData, bitmap.bitmapData + out_stride * height);
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
    bool black = false;
    std::string error;
    std::string name;
    std::size_t current = 0;
    uint64_t timer_seconds = 0;

    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      document = impl_->pdf_document;
      slides = impl_->slides;
      loading = impl_->loading;
      loaded = impl_->loaded;
      black = impl_->black;
      error = impl_->error;
      name = impl_->name;
      current = impl_->current;
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
      NSString *subtitle = loading ? @"Loading presentation…" :
        (error.empty() ? @"Choose a .pptx in source properties" : ToNSString(error));
      DrawCenteredMessage(@"PPTBridge SK", subtitle, NSMakeRect(0, 0, width, height - 56));
      [NSGraphicsContext restoreGraphicsState];
      out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
      out_pixels.assign(bitmap.bitmapData, bitmap.bitmapData + out_stride * height);
      return true;
    }

    CGFloat margin = 18.0;
    CGFloat right_width = std::max<CGFloat>(320.0, width * 0.28);
    NSRect left = NSMakeRect(margin, margin + 60, width - right_width - margin * 3, height - 56 - margin * 2 - 60);
    NSRect right = NSMakeRect(NSMaxX(left) + margin, margin + 60, right_width, height - 56 - margin * 2 - 60);

    FillRect(left, [NSColor blackColor]);
    DrawPageThumbnail(document, current, left);

    NSRect slide_count = NSMakeRect(left.origin.x, 18, 180, 30);
    DrawLabel(
      [NSString stringWithFormat:@"Slide %lu / %lu",
        static_cast<unsigned long>(current + 1),
        static_cast<unsigned long>(document.pageCount)],
      slide_count,
      [NSColor colorWithWhite:0.75 alpha:1.0],
      [NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightMedium]);

    NSRect next_box = NSMakeRect(right.origin.x, right.origin.y + right.size.height - 220, right.size.width, 200);
    [[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.15 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:next_box xRadius:18 yRadius:18] fill];
    DrawLabel(@"Next Slide", NSMakeRect(next_box.origin.x + 16, NSMaxY(next_box) - 28, 200, 18), [NSColor colorWithWhite:0.78 alpha:1.0], [NSFont boldSystemFontOfSize:13]);
    if (current + 1 < static_cast<std::size_t>(document.pageCount)) {
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
    NSString *notes_text = notes.empty() ? @"No presenter notes on this slide" : ToNSString(notes);
    NSDictionary *notes_attrs = @{
      NSForegroundColorAttributeName : notes.empty() ? [NSColor colorWithWhite:0.55 alpha:1.0] : [NSColor colorWithWhite:0.95 alpha:1.0],
      NSFontAttributeName : [NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightRegular],
    };
    [notes_text drawInRect:NSInsetRect(notes_box, 16, 20) withAttributes:notes_attrs];

    [NSGraphicsContext restoreGraphicsState];

    out_stride = static_cast<uint32_t>(bitmap.bytesPerRow);
    out_pixels.assign(bitmap.bitmapData, bitmap.bitmapData + out_stride * height);
    return true;
  }
}

}  // namespace pptbridge
