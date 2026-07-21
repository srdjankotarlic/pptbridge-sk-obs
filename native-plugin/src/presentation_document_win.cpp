#include "presentation_document.hpp"

#ifdef _WIN32

#include <obs-module.h>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>
#include <gdiplus.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace fs = std::filesystem;
using namespace Gdiplus;

namespace pptbridge {

namespace {

constexpr const wchar_t *kPowerShellExe = L"powershell.exe";
constexpr uint32_t kExportWidth = 1920;
constexpr uint32_t kExportHeight = 1080;
constexpr DWORD kExportProcessTimeoutMs = 300000;
constexpr DWORD kLiveStartProcessTimeoutMs = 90000;
constexpr DWORD kLiveStopProcessTimeoutMs = 30000;
constexpr DWORD kLiveCommandProcessTimeoutMs = 20000;
constexpr DWORD kProcessPollMs = 20;

struct CachedSlide {
  std::wstring image_path;
  SlideMetadata meta;
};

struct ParsedDeckData {
  std::vector<CachedSlide> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  double slide_aspect_ratio = 0.0;
  bool media_scan_complete = true;
};

struct LiveSnapshot {
  bool running = false;
  size_t current_slide = 0;
  size_t slide_count = 0;
  std::string presentation_title;
  std::string window_title;
  double slide_aspect_ratio = 0.0;
};

uint64_t StableHash(std::string_view value)
{
  uint64_t hash = 1469598103934665603ull;
  for (const unsigned char ch : value) {
    hash ^= static_cast<uint64_t>(ch);
    hash *= 1099511628211ull;
  }
  return hash;
}

std::wstring Utf8ToWide(const std::string &value)
{
  if (value.empty()) {
    return {};
  }

  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 1) {
    return {};
  }

  std::wstring wide(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), size);
  return wide;
}

std::string WideToUtf8(const std::wstring &value)
{
  if (value.empty()) {
    return {};
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return {};
  }

  std::string utf8(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::string ToLowerCopy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

std::string LowerExtensionForPath(const std::string &path)
{
  return ToLowerCopy(fs::path(Utf8ToWide(path)).extension().string());
}

bool IsSupportedPowerPointExtension(const std::string &path)
{
  const auto extension = LowerExtensionForPath(path);
  return extension == ".ppt" ||
         extension == ".pptx" ||
         extension == ".pptm" ||
         extension == ".ppsx" ||
         extension == ".potx" ||
         extension == ".potm";
}

bool IsPdfExtension(const std::string &path)
{
  return LowerExtensionForPath(path) == ".pdf";
}

std::wstring QuoteWindowsArg(const std::wstring &arg)
{
  if (arg.empty()) {
    return L"\"\"";
  }

  bool needs_quotes = false;
  for (const wchar_t ch : arg) {
    if (ch == L' ' || ch == L'\t' || ch == L'"') {
      needs_quotes = true;
      break;
    }
  }

  if (!needs_quotes) {
    return arg;
  }

  std::wstring quoted;
  quoted.push_back(L'"');
  size_t backslashes = 0;
  for (const wchar_t ch : arg) {
    if (ch == L'\\') {
      backslashes += 1;
      continue;
    }

    if (ch == L'"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(L'"');
      backslashes = 0;
      continue;
    }

    if (backslashes > 0) {
      quoted.append(backslashes, L'\\');
      backslashes = 0;
    }
    quoted.push_back(ch);
  }

  if (backslashes > 0) {
    quoted.append(backslashes * 2, L'\\');
  }

  quoted.push_back(L'"');
  return quoted;
}

std::wstring BuildCommandLine(const std::vector<std::wstring> &args)
{
  std::wstring command_line;
  bool first = true;
  for (const auto &arg : args) {
    if (!first) {
      command_line.push_back(L' ');
    }
    first = false;
    command_line.append(QuoteWindowsArg(arg));
  }
  return command_line;
}

bool RunProcessCapture(
  const std::vector<std::wstring> &args,
  DWORD timeout_ms,
  std::string &out_output,
  int &out_exit_code)
{
  out_output.clear();
  out_exit_code = -1;

  SECURITY_ATTRIBUTES attributes = {};
  attributes.nLength = sizeof(attributes);
  attributes.bInheritHandle = TRUE;

  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &attributes, 0)) {
    return false;
  }

  SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = write_pipe;
  startup.hStdError = write_pipe;

  PROCESS_INFORMATION process = {};
  std::wstring command_line = BuildCommandLine(args);
  std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
  mutable_command.push_back(L'\0');

  const BOOL created = CreateProcessW(
    nullptr,
    mutable_command.data(),
    nullptr,
    nullptr,
    TRUE,
    CREATE_NO_WINDOW,
    nullptr,
    nullptr,
    &startup,
    &process);

  CloseHandle(write_pipe);

  if (!created) {
    CloseHandle(read_pipe);
    return false;
  }

  char buffer[4096];
  const ULONGLONG started_at = GetTickCount64();
  bool process_done = false;
  bool timed_out = false;

  while (true) {
    DWORD available = 0;
    if (!PeekNamedPipe(read_pipe, nullptr, 0, nullptr, &available, nullptr)) {
      break;
    }

    while (available > 0) {
      DWORD bytes_read = 0;
      const DWORD to_read = std::min<DWORD>(available, sizeof(buffer));
      if (!ReadFile(read_pipe, buffer, to_read, &bytes_read, nullptr) || bytes_read == 0) {
        available = 0;
        break;
      }
      out_output.append(buffer, buffer + bytes_read);

      available = 0;
      if (!PeekNamedPipe(read_pipe, nullptr, 0, nullptr, &available, nullptr)) {
        break;
      }
    }

    const DWORD wait_result = WaitForSingleObject(process.hProcess, process_done ? 0 : kProcessPollMs);
    if (wait_result == WAIT_OBJECT_0) {
      if (process_done) {
        break;
      }
      process_done = true;
      continue;
    }
    if (wait_result == WAIT_FAILED) {
      break;
    }
    if (process_done && wait_result == WAIT_TIMEOUT) {
      break;
    }

    if (!process_done && GetTickCount64() - started_at >= timeout_ms) {
      timed_out = true;
      TerminateProcess(process.hProcess, 1);
      WaitForSingleObject(process.hProcess, 2000);
      process_done = true;
    }
  }

  DWORD exit_code = 0;
  GetExitCodeProcess(process.hProcess, &exit_code);
  out_exit_code = static_cast<int>(exit_code);
  if (timed_out) {
    if (!out_output.empty()) {
      out_output.append("\n");
    }
    out_output.append("Process timed out after ");
    out_output.append(std::to_string(timeout_ms / 1000));
    out_output.append(" seconds.");
  }

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  CloseHandle(read_pipe);
  return !timed_out;
}

std::wstring GetLocalAppDataPath()
{
  PWSTR raw = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw)) && raw) {
    std::wstring path(raw);
    CoTaskMemFree(raw);
    return path;
  }

  wchar_t temp[MAX_PATH] = {};
  GetTempPathW(MAX_PATH, temp);
  return temp;
}

fs::path PluginCacheRoot()
{
  fs::path root(GetLocalAppDataPath());
  root /= L"PPTBridgeSK";
  root /= L"windows-cache";
  std::error_code ec;
  fs::create_directories(root, ec);
  return root;
}

fs::path CacheRootForDeck(const std::string &pptx_path)
{
  std::wstringstream folder_name;
  folder_name << L"deck-" << std::hex << StableHash(pptx_path);
  fs::path root = PluginCacheRoot() / folder_name.str();
  std::error_code ec;
  fs::create_directories(root, ec);
  return root;
}

std::string CurrentFileStamp(const fs::path &path)
{
  std::error_code ec;
  const auto size = fs::file_size(path, ec);
  const auto timestamp = fs::last_write_time(path, ec).time_since_epoch().count();
  std::ostringstream stamp;
  stamp << size << ":" << timestamp;
  return stamp.str();
}

bool WriteUtf8File(const fs::path &path, const std::string &body)
{
  std::error_code ec;
  fs::create_directories(path.parent_path(), ec);
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  if (!stream.is_open()) {
    return false;
  }

  stream.write(body.data(), static_cast<std::streamsize>(body.size()));
  return stream.good();
}

std::string ReadUtf8File(const fs::path &path)
{
  std::ifstream stream(path, std::ios::binary);
  if (!stream.is_open()) {
    return {};
  }

  std::ostringstream contents;
  contents << stream.rdbuf();
  return contents.str();
}

std::string TrimLine(std::string line)
{
  while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
    line.pop_back();
  }
  return line;
}

std::vector<std::string> SplitLines(const std::string &text)
{
  std::vector<std::string> lines;
  std::stringstream stream(text);
  std::string line;
  while (std::getline(stream, line)) {
    lines.push_back(TrimLine(line));
  }
  return lines;
}

std::string TrimWhitespaceCopy(std::string value)
{
  value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char ch) {
    return !std::isspace(ch);
  }));
  value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char ch) {
    return !std::isspace(ch);
  }).base(), value.end());
  return value;
}

std::string LiveRecoveryErrorMessage(const std::string &detail)
{
  std::string message =
    "PowerPoint slideshow is not available. Click Start / Restart PowerPoint Live Mode in source properties to recover.";
  const std::string trimmed = TrimWhitespaceCopy(detail);
  if (!trimmed.empty()) {
    message += " Last PowerPoint response: " + trimmed;
  }
  return message;
}

std::string UnescapePipeValue(const std::string &value)
{
  std::string unescaped;
  unescaped.reserve(value.size());
  bool escaping = false;
  for (const char ch : value) {
    if (!escaping) {
      if (ch == '\\') {
        escaping = true;
      } else {
        unescaped.push_back(ch);
      }
      continue;
    }

    escaping = false;
    switch (ch) {
    case 'n':
      unescaped.push_back('\n');
      break;
    case 'r':
      unescaped.push_back('\r');
      break;
    case 'p':
      unescaped.push_back('|');
      break;
    case '\\':
      unescaped.push_back('\\');
      break;
    default:
      unescaped.push_back(ch);
      break;
    }
  }

  if (escaping) {
    unescaped.push_back('\\');
  }

  return unescaped;
}

std::string EscapePipeValue(const std::string &value)
{
  std::string escaped;
  escaped.reserve(value.size() + 8);
  for (const char ch : value) {
    switch (ch) {
    case '\\':
      escaped += "\\\\";
      break;
    case '|':
      escaped += "\\p";
      break;
    case '\r':
      escaped += "\\r";
      break;
    case '\n':
      escaped += "\\n";
      break;
    default:
      escaped.push_back(ch);
      break;
    }
  }
  return escaped;
}

std::vector<std::string> SplitPipeLine(const std::string &line)
{
  std::vector<std::string> parts;
  std::string current;
  bool escaping = false;

  for (const char ch : line) {
    if (!escaping && ch == '|') {
      parts.push_back(current);
      current.clear();
      continue;
    }

    if (!escaping && ch == '\\') {
      escaping = true;
      current.push_back(ch);
      continue;
    }

    escaping = false;
    current.push_back(ch);
  }

  parts.push_back(current);
  for (auto &part : parts) {
    part = UnescapePipeValue(part);
  }
  return parts;
}

bool SaveCachedSlides(
  const fs::path &metadata_path,
  const std::string &stamp,
  const std::vector<CachedSlide> &slides,
  const std::vector<std::vector<EmbeddedMedia>> &media_by_slide,
  double slide_aspect_ratio,
  bool media_scan_complete)
{
  std::ostringstream output;
  output << "STAMP|" << stamp << "\n";
  output << "ASPECT|" << slide_aspect_ratio << "\n";
  output << "MEDIA_SCAN|" << (media_scan_complete ? "1" : "0") << "\n";
  for (size_t index = 0; index < slides.size(); ++index) {
    const auto &slide = slides[index];
    output << "SLIDE|"
           << (index + 1) << "|"
           << EscapePipeValue(WideToUtf8(slide.image_path)) << "|"
           << EscapePipeValue(slide.meta.title) << "|"
           << EscapePipeValue(slide.meta.notes) << "\n";
  }

  for (size_t index = 0; index < media_by_slide.size(); ++index) {
    for (const auto &media : media_by_slide[index]) {
      output << "MEDIA|"
             << (index + 1) << "|"
             << (media.kind == EmbeddedMediaKind::Audio ? "audio" : "video") << "|"
             << EscapePipeValue(media.file_path) << "|"
             << EscapePipeValue(media.original_entry) << "|"
             << media.x << "|"
             << media.y << "|"
             << media.width << "|"
             << media.height << "|"
             << (media.autoplay ? "1" : "0") << "|"
             << (media.loop ? "1" : "0") << "\n";
    }
  }

  return WriteUtf8File(metadata_path, output.str());
}

bool CachedSlideImagesExist(const std::vector<CachedSlide> &slides)
{
  if (slides.empty()) {
    return false;
  }

  for (const auto &slide : slides) {
    if (slide.image_path.empty()) {
      return false;
    }

    std::error_code ec;
    if (!fs::exists(fs::path(slide.image_path), ec) || ec) {
      return false;
    }
  }

  return true;
}

bool LoadCachedSlides(
  const fs::path &metadata_path,
  const std::string &stamp,
  bool require_media_scan,
  ParsedDeckData &out_deck)
{
  const auto contents = ReadUtf8File(metadata_path);
  if (contents.empty()) {
    return false;
  }

  std::vector<CachedSlide> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  double slide_aspect_ratio = 0.0;
  bool media_scan_complete = true;
  for (const auto &line : SplitLines(contents)) {
    if (line.rfind("STAMP|", 0) == 0) {
      if (line.substr(6) != stamp) {
        return false;
      }
      continue;
    }

    if (line.rfind("ASPECT|", 0) == 0) {
      try {
        slide_aspect_ratio = std::stod(line.substr(7));
      } catch (...) {
        slide_aspect_ratio = 0.0;
      }
      continue;
    }

    if (line.rfind("MEDIA_SCAN|", 0) == 0) {
      media_scan_complete = line.substr(11) != "0";
      continue;
    }

    if (line.rfind("SLIDE|", 0) != 0) {
      continue;
    }

    const auto parts = SplitPipeLine(line);
    if (parts.size() < 5) {
      continue;
    }

    CachedSlide slide;
    slide.image_path = Utf8ToWide(parts[2]);
    slide.meta.title = parts[3];
    slide.meta.notes = parts[4];
    slides.push_back(std::move(slide));
    if (media_by_slide.size() < slides.size()) {
      media_by_slide.resize(slides.size());
    }
  }

  for (const auto &line : SplitLines(contents)) {
    if (line.rfind("MEDIA|", 0) != 0) {
      continue;
    }

    const auto parts = SplitPipeLine(line);
    if (parts.size() < 11) {
      continue;
    }

    size_t slide_index = 0;
    try {
      slide_index = static_cast<size_t>(std::stoul(parts[1]));
    } catch (...) {
      continue;
    }
    if (slide_index == 0) {
      continue;
    }

    if (media_by_slide.size() < slide_index) {
      media_by_slide.resize(slide_index);
    }

    EmbeddedMedia media;
    media.kind = parts[2] == "audio" ? EmbeddedMediaKind::Audio : EmbeddedMediaKind::Video;
    media.file_path = parts[3];
    media.original_entry = parts[4];
    try {
      media.x = std::stod(parts[5]);
      media.y = std::stod(parts[6]);
      media.width = std::stod(parts[7]);
      media.height = std::stod(parts[8]);
    } catch (...) {
      continue;
    }
    media.autoplay = parts[9] != "0";
    media.loop = parts[10] == "1";
    media_by_slide[slide_index - 1].push_back(std::move(media));
  }

  if ((require_media_scan && !media_scan_complete) ||
      !CachedSlideImagesExist(slides) ||
      slide_aspect_ratio < 0.2 || slide_aspect_ratio > 10.0) {
    return false;
  }

  if (media_by_slide.size() < slides.size()) {
    media_by_slide.resize(slides.size());
  }

  out_deck.slides = std::move(slides);
  out_deck.media_by_slide = std::move(media_by_slide);
  out_deck.slide_aspect_ratio = slide_aspect_ratio;
  out_deck.media_scan_complete = media_scan_complete;
  return true;
}

std::string BuildWindowsPowerShellScript()
{
  std::string script;
  script.reserve(65536);
  script += R"POWERSHELL(
param(
  [Parameter(Mandatory = $true)][string]$Mode,
  [string]$PptxPath,
  [string]$CacheDir,
  [int]$Width = 1920,
  [int]$Height = 1080,
  [int]$TargetSlide = 1,
  [switch]$SkipEmbeddedMedia
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Escape-PPTBridgeValue([string]$Value) {
  if ($null -eq $Value) { return "" }
  $Value = $Value.Replace('\', '\\')
  $Value = $Value.Replace('|', '\p')
  $Value = $Value.Replace("`r", '\r')
  $Value = $Value.Replace("`n", '\n')
  return $Value
}

function Normalize-PPTBridgeFilePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $normalized = $Path.Trim()
  if ($normalized.StartsWith("//")) {
    $normalized = "\\" + $normalized.Substring(2)
  }
  return $normalized.Replace('/', '\')
}

function Open-PPTBridgeZipArchive([string]$Path) {
  $normalizedPath = Normalize-PPTBridgeFilePath $Path
  if ([string]::IsNullOrWhiteSpace($normalizedPath)) { return $null }

  $stream = $null
  $archive = $null
  try {
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $stream = [System.IO.File]::Open(
      $normalizedPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      $share)

    $signature = New-Object byte[] 2
    $signatureLength = $stream.Read($signature, 0, $signature.Length)
    $stream.Position = 0
    if ($signatureLength -ne 2 -or $signature[0] -ne 0x50 -or $signature[1] -ne 0x4B) {
      $stream.Dispose()
      $stream = $null
      return $null
    }

    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)

    # ZipArchive validates some malformed and legacy binary files lazily.
    # Force that validation here so classic .ppt files cleanly use COM export.
    $null = $archive.Entries.Count
    return $archive
  } catch {
    if ($null -ne $archive) {
      try { $archive.Dispose() } catch {}
      $stream = $null
    } elseif ($null -ne $stream) {
      try { $stream.Dispose() } catch {}
    }
    return $null
  }
}

function Resolve-PPTBridgeZipTarget([string]$BaseEntry, [string]$Target) {
  if ([string]::IsNullOrWhiteSpace($Target)) { return "" }
  $baseUri = [System.Uri]("https://pptbridge.local/" + $BaseEntry.Replace('\', '/'))
  $resolved = [System.Uri]::new($baseUri, $Target)
  return $resolved.AbsolutePath.TrimStart('/')
}

function Get-PPTBridgeZipEntryText($Archive, [string]$EntryPath) {
  if ($null -eq $Archive -or [string]::IsNullOrWhiteSpace($EntryPath)) { return $null }
  $entry = $Archive.GetEntry($EntryPath.Replace('\', '/'))
  if ($null -eq $entry) { return $null }
  $stream = $entry.Open()
  $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))
  try {
    return $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Get-PPTBridgeZipRelationships($Archive, [string]$EntryPath) {
  $map = @{}
  $xmlText = Get-PPTBridgeZipEntryText $Archive $EntryPath
  if ([string]::IsNullOrWhiteSpace($xmlText)) { return $map }
  [xml]$xml = $xmlText
  foreach ($relationship in @($xml.Relationships.Relationship)) {
    if ($null -eq $relationship) { continue }
    $map[[string]$relationship.Id] = [pscustomobject]@{
      Type = [string]$relationship.Type
      Target = [string]$relationship.Target
      External = ([string]$relationship.TargetMode -eq "External")
    }
  }
  return $map
}

function Get-PPTBridgeSlideEntries($Archive) {
  $presentationXml = Get-PPTBridgeZipEntryText $Archive "ppt/presentation.xml"
  if ([string]::IsNullOrWhiteSpace($presentationXml)) { return @() }

  $relationships = Get-PPTBridgeZipRelationships $Archive "ppt/_rels/presentation.xml.rels"
  [xml]$presentation = $presentationXml
  $slideEntries = New-Object System.Collections.Generic.List[string]
  foreach ($slideId in @($presentation.SelectNodes("//*[local-name()='sldIdLst']/*[local-name()='sldId']"))) {
    if ($null -eq $slideId) { continue }
    $relationshipId = $slideId.GetAttribute("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
    if ([string]::IsNullOrWhiteSpace($relationshipId)) { continue }
    $relationship = $relationships[$relationshipId]
    if ($null -eq $relationship -or [string]::IsNullOrWhiteSpace($relationship.Target)) { continue }
    [void]$slideEntries.Add((Resolve-PPTBridgeZipTarget "ppt/presentation.xml" $relationship.Target))
  }
  return @($slideEntries)
}

function Get-PPTBridgeSlideSize($Archive) {
  $presentationXml = Get-PPTBridgeZipEntryText $Archive "ppt/presentation.xml"
  if ([string]::IsNullOrWhiteSpace($presentationXml)) {
    return [pscustomobject]@{ Width = 0.0; Height = 0.0 }
  }

  [xml]$presentation = $presentationXml
  $sizeNode = $presentation.SelectSingleNode("//*[local-name()='sldSz']")
  if ($null -eq $sizeNode) {
    return [pscustomobject]@{ Width = 0.0; Height = 0.0 }
  }

  return [pscustomobject]@{
    Width = [double]$sizeNode.cx
    Height = [double]$sizeNode.cy
  }
}

function Get-PPTBridgeRelationshipIds($Node) {
  $ids = New-Object 'System.Collections.Generic.HashSet[string]'
  $allNodes = New-Object System.Collections.Generic.List[System.Xml.XmlNode]
  [void]$allNodes.Add($Node)
  foreach ($child in @($Node.SelectNodes(".//*"))) {
    [void]$allNodes.Add($child)
  }

  foreach ($candidate in $allNodes) {
    if ($null -eq $candidate -or $null -eq $candidate.Attributes) { continue }
    foreach ($attribute in @($candidate.Attributes)) {
      if ($null -eq $attribute) { continue }
      if (@("embed", "link", "id") -contains $attribute.LocalName -and [string]$attribute.Value -like "rId*") {
        [void]$ids.Add([string]$attribute.Value)
      }
    }
  }

  return @($ids)
}

function Test-PPTBridgeMediaRelationship($Relationship, [string]$ResolvedTarget) {
  if ($null -eq $Relationship -or $Relationship.External) { return $false }
  $extension = [System.IO.Path]::GetExtension($ResolvedTarget).ToLowerInvariant()
  if (@(".bmp", ".emf", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".tif", ".tiff", ".wmf") -contains $extension) {
    return $false
  }
  if (@(".aac", ".aif", ".aiff", ".avi", ".flac", ".m4a", ".m4v", ".mkv", ".mov", ".mp3", ".mp4", ".mpeg", ".mpg", ".ogg", ".wav", ".webm", ".wma", ".wmv") -contains $extension) {
    return $true
  }

  $type = ([string]$Relationship.Type).ToLowerInvariant()
  return $type.Contains("media") -or $type.Contains("video") -or $type.Contains("audio")
}

function Get-PPTBridgeMediaKind($Relationship, [string]$ResolvedTarget) {
  $extension = [System.IO.Path]::GetExtension($ResolvedTarget).ToLowerInvariant()
  $type = ([string]$Relationship.Type).ToLowerInvariant()
  if (@(".aac", ".aif", ".aiff", ".flac", ".m4a", ".mp3", ".ogg", ".wav", ".wma") -contains $extension -or $type.Contains("audio")) {
    return "audio"
  }
  return "video"
}

function Get-PPTBridgeNormalizedRect($Node, [double]$SlideWidth, [double]$SlideHeight) {
  if ($SlideWidth -le 0 -or $SlideHeight -le 0) {
    return [pscustomobject]@{ X = 0.0; Y = 0.0; Width = 1.0; Height = 1.0 }
  }

  $offNode = $Node.SelectSingleNode(".//*[local-name()='off']")
  $extNode = $Node.SelectSingleNode(".//*[local-name()='ext']")
  if ($null -eq $offNode -or $null -eq $extNode) {
    return [pscustomobject]@{ X = 0.0; Y = 0.0; Width = 1.0; Height = 1.0 }
  }

  return [pscustomobject]@{
    X = ([double]$offNode.x) / $SlideWidth
    Y = ([double]$offNode.y) / $SlideHeight
    Width = ([double]$extNode.cx) / $SlideWidth
    Height = ([double]$extNode.cy) / $SlideHeight
  }
}

function Export-PPTBridgeZipEntry($Archive, [string]$EntryPath, [string]$DestinationRoot) {
  if ($null -eq $Archive -or [string]::IsNullOrWhiteSpace($EntryPath) -or [string]::IsNullOrWhiteSpace($DestinationRoot)) {
    return ""
  }

  $entry = $Archive.GetEntry($EntryPath.Replace('\', '/'))
  if ($null -eq $entry) { return "" }

  $destinationPath = Join-Path $DestinationRoot ($EntryPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
  $destinationDirectory = Split-Path -Parent $destinationPath
  if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
  }

  if (-not (Test-Path -LiteralPath $destinationPath) -or ((Get-Item -LiteralPath $destinationPath).Length -ne $entry.Length)) {
    $input = $entry.Open()
    $output = [System.IO.File]::Open($destinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
      $input.CopyTo($output)
    } finally {
      $output.Dispose()
      $input.Dispose()
    }
  }

  return $destinationPath
}

)POWERSHELL";
  script += R"POWERSHELL(
function Get-PPTBridgeTrailingNumber([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return [int]::MaxValue }
  if ($Name -match '(\d+)$') { return [int]$Matches[1] }
  return [int]::MaxValue
}

function Get-PPTBridgeExportedImageFiles([string]$SlidesDir) {
  if ([string]::IsNullOrWhiteSpace($SlidesDir) -or -not (Test-Path -LiteralPath $SlidesDir)) {
    return @()
  }

  $imageExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff")
  $files = @(Get-ChildItem -LiteralPath $SlidesDir -File -ErrorAction SilentlyContinue |
    Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() })

  return @($files | Sort-Object `
    @{ Expression = { Get-PPTBridgeTrailingNumber $_.BaseName } }, `
    @{ Expression = { $_.Name } })
}

function Wait-PPTBridgeExportedImageFiles([string]$SlidesDir, [int]$ExpectedCount) {
  if ($ExpectedCount -lt 1) { return @() }

  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  $lastSignature = ""
  $stablePolls = 0
  $files = @()

  do {
    $files = @(Get-PPTBridgeExportedImageFiles $SlidesDir)
    if ($files.Count -ge $ExpectedCount) {
      $current = @($files | Select-Object -First $ExpectedCount)
      $signature = (($current | ForEach-Object {
        "{0}|{1}|{2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks
      }) -join ";")

      if ($signature -eq $lastSignature) {
        $stablePolls += 1
      } else {
        $lastSignature = $signature
        $stablePolls = 0
      }

      if ($stablePolls -ge 1) {
        return $current
      }
    }
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)

  return @($files | Select-Object -First $ExpectedCount)
}

function Resolve-PPTBridgeExportedSlideFile($ExportedFiles, [int]$Index) {
  if ($null -eq $ExportedFiles -or $Index -lt 1) { return "" }

  $files = @($ExportedFiles)
  if ($files.Count -eq 0) { return "" }

  $localizedNames = @(
    "Slide{0}",
    "Slide {0}",
    "Folie{0}",
    "Folie {0}",
    "Diapositive{0}",
    "Diapositive {0}"
  ) | ForEach-Object { $_ -f $Index }

  foreach ($name in $localizedNames) {
    $match = @($files | Where-Object { $_.BaseName -ieq $name } | Select-Object -First 1)
    if ($match.Count -gt 0) { return [string]$match[0].FullName }
  }

  $numbered = @($files | Where-Object { (Get-PPTBridgeTrailingNumber $_.BaseName) -eq $Index } | Select-Object -First 1)
  if ($numbered.Count -gt 0) { return [string]$numbered[0].FullName }

  if ($Index -le $files.Count) {
    return [string]$files[$Index - 1].FullName
  }

  return ""
}

function Get-PPTBridgeMediaForSlide($Archive, [string]$SlideEntry, [string]$CacheDir, [double]$SlideWidth, [double]$SlideHeight, $ExtractedCache) {
  $results = New-Object System.Collections.Generic.List[object]
  $signatures = New-Object 'System.Collections.Generic.HashSet[string]'
  $slideXml = Get-PPTBridgeZipEntryText $Archive $SlideEntry
  if ([string]::IsNullOrWhiteSpace($slideXml)) { return $results.ToArray() }

  $relsEntry = ([System.IO.Path]::GetDirectoryName($SlideEntry).Replace('\', '/')) + "/_rels/" + [System.IO.Path]::GetFileName($SlideEntry) + ".rels"
  $relationships = Get-PPTBridgeZipRelationships $Archive $relsEntry
  if ($relationships.Count -eq 0) { return $results.ToArray() }

  [xml]$slideDocument = $slideXml
  $shapeNodes = @($slideDocument.SelectNodes("//*[local-name()='spTree']/*"))
  foreach ($shape in $shapeNodes) {
    if ($null -eq $shape) { continue }

    $candidateIds = Get-PPTBridgeRelationshipIds $shape
    if ($candidateIds.Count -eq 0) { continue }

    $best = $null
    $bestTarget = ""
    $bestScore = -1
    foreach ($relationshipId in $candidateIds) {
      $relationship = $relationships[$relationshipId]
      if ($null -eq $relationship) { continue }
      $resolvedTarget = Resolve-PPTBridgeZipTarget $SlideEntry ([string]$relationship.Target)
      if (-not (Test-PPTBridgeMediaRelationship $relationship $resolvedTarget)) { continue }

      $score = 10
      $type = ([string]$relationship.Type).ToLowerInvariant()
      if ($type.Contains("video") -or $type.Contains("audio")) { $score += 20 }
      $extension = [System.IO.Path]::GetExtension($resolvedTarget).ToLowerInvariant()
      if (@(".aac", ".aif", ".aiff", ".avi", ".flac", ".m4a", ".m4v", ".mkv", ".mov", ".mp3", ".mp4", ".mpeg", ".mpg", ".ogg", ".wav", ".webm", ".wma", ".wmv") -contains $extension) {
        $score += 10
      }

      if ($score -gt $bestScore) {
        $best = $relationship
        $bestTarget = $resolvedTarget
        $bestScore = $score
      }
    }

    if ($null -eq $best -or [string]::IsNullOrWhiteSpace($bestTarget)) { continue }

    $normalizedRect = Get-PPTBridgeNormalizedRect $shape $SlideWidth $SlideHeight
    $extractedPath = ""
    if ($ExtractedCache.ContainsKey($bestTarget)) {
      $extractedPath = [string]$ExtractedCache[$bestTarget]
    } else {
      $extractedPath = Export-PPTBridgeZipEntry $Archive $bestTarget (Join-Path $CacheDir "embedded-media")
      if ([string]::IsNullOrWhiteSpace($extractedPath)) { continue }
      $ExtractedCache[$bestTarget] = $extractedPath
    }

    $signature = "{0}|{1}|{2}|{3}|{4}" -f $bestTarget, $normalizedRect.X, $normalizedRect.Y, $normalizedRect.Width, $normalizedRect.Height
    if (-not $signatures.Add($signature)) { continue }

    [void]$results.Add([pscustomobject]@{
      Kind = Get-PPTBridgeMediaKind $best $bestTarget
      FilePath = $extractedPath
      OriginalEntry = $bestTarget
      X = $normalizedRect.X
      Y = $normalizedRect.Y
      Width = $normalizedRect.Width
      Height = $normalizedRect.Height
      Autoplay = $true
      Loop = $false
    })
  }

  return $results.ToArray()
}

function Get-PPTBridgeApp([bool]$CreateIfMissing) {
  try {
    return [System.Runtime.InteropServices.Marshal]::GetActiveObject("PowerPoint.Application")
  } catch {
    if ($CreateIfMissing) {
      return New-Object -ComObject PowerPoint.Application
    }
    return $null
  }
}

function Set-PPTBridgePowerPointVisible($App) {
  if ($null -eq $App) { return }
  try {
    $App.Visible = -1
  } catch {
    try { $App.Visible = [int]-1 } catch {}
  }
}

function Find-PPTBridgePresentation($App, [string]$Path) {
  if ($null -eq $App -or [string]::IsNullOrWhiteSpace($Path)) { return $null }
  $normalizedPath = Normalize-PPTBridgeFilePath $Path
  $targetName = [System.IO.Path]::GetFileName($normalizedPath)
  foreach ($presentation in @($App.Presentations)) {
    try {
      $presentationPath = Normalize-PPTBridgeFilePath ([string]$presentation.FullName)
      if ($presentationPath -ieq $normalizedPath -or $presentation.Name -ieq $targetName) {
        return $presentation
      }
    } catch {}
  }
  return $null
}

function Open-PPTBridgePresentation($App, [string]$Path, [bool]$WithWindow) {
  $normalizedPath = Normalize-PPTBridgeFilePath $Path
  $presentation = Find-PPTBridgePresentation $App $normalizedPath
  if ($presentation) { return $presentation }
  return $App.Presentations.Open($normalizedPath, $false, $false, $WithWindow)
}

function Get-PPTBridgeWindow($App, $Presentation) {
  if ($null -eq $App -or $null -eq $Presentation) { return $null }
  foreach ($window in @($App.SlideShowWindows)) {
    try {
      if ($window.Presentation.FullName -eq $Presentation.FullName -or
          $window.Presentation.Name -eq $Presentation.Name) {
        return $window
      }
    } catch {}
  }
  return $null
}

function Get-PPTBridgeNotes($Slide) {
  $notes = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($shape in @($Slide.NotesPage.Shapes)) {
      try {
        if ($shape.HasTextFrame -ne -1) { continue }
        if ($shape.TextFrame.HasText -ne -1) { continue }
        $text = [string]$shape.TextFrame.TextRange.Text
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $trimmed = $text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
          [void]$notes.Add($trimmed)
        }
      } catch {}
    }
  } catch {}

  return (($notes | Select-Object -Unique) -join "`n`n")
}

function Emit-PPTBridgeSnapshot($Window, $Presentation) {
  Write-Output "OK"
  if ($null -eq $Window -or $null -eq $Presentation) {
    Write-Output "RUNNING|0"
    Write-Output "SLIDE|0"
    Write-Output "COUNT|0"
    Write-Output "TITLE|"
    Write-Output "WINDOW|"
    Write-Output "ASPECT|0"
    return
  }

  $slideCount = 0
  try { $slideCount = [int]$Presentation.Slides.Count } catch {}
  $current = 0
  try { $current = [int]$Window.View.CurrentShowPosition } catch {}
  $title = ""
  try { $title = [string]$Presentation.Name } catch {}
  $windowTitle = "PowerPoint Slide Show - [" + [System.IO.Path]::GetFileNameWithoutExtension($title) + "]"
  $slideAspect = 0.0
  try {
    $slideWidth = [double]$Presentation.PageSetup.SlideWidth
    $slideHeight = [double]$Presentation.PageSetup.SlideHeight
    if ($slideWidth -gt 0.0 -and $slideHeight -gt 0.0) {
      $slideAspect = $slideWidth / $slideHeight
    }
  } catch {}

  Write-Output "RUNNING|1"
  Write-Output ("SLIDE|{0}" -f $current)
  Write-Output ("COUNT|{0}" -f $slideCount)
  Write-Output ("TITLE|{0}" -f (Escape-PPTBridgeValue $title))
  Write-Output ("WINDOW|{0}" -f (Escape-PPTBridgeValue $windowTitle))
  Write-Output ("ASPECT|" + $slideAspect.ToString("R", [Globalization.CultureInfo]::InvariantCulture))
}

)POWERSHELL";
  script += R"POWERSHELL(
function Start-PPTBridgePendingMedia($Window, $Presentation) {
  if ($null -eq $Window -or $null -eq $Presentation) { return $false }

  $position = 0
  try { $position = [int]$Window.View.CurrentShowPosition } catch {}
  if ($position -lt 1) { return $false }

  $slide = $null
  try { $slide = $Presentation.Slides.Item($position) } catch { return $false }
  foreach ($shape in @($slide.Shapes)) {
    try {
      $mediaType = 0
      try { $mediaType = [int]$shape.MediaType } catch {}
      if ($mediaType -eq 0) { continue }

      $playOnEntry = $false
      try { $playOnEntry = [bool]$shape.AnimationSettings.PlaySettings.PlayOnEntry } catch {}
      if ($playOnEntry) { continue }

      $player = $null
      try { $player = $Window.View.Player([int]$shape.Id) } catch {}
      if ($null -eq $player) { continue }

      $state = -1
      $currentPosition = 0.0
      try { $state = [int]$player.State } catch {}
      try { $currentPosition = [double]$player.CurrentPosition } catch {}
      if ($state -eq 3 -or ($state -eq 2 -and $currentPosition -le 0.0)) {
        try {
          $player.Play()
          return $true
        } catch {}
      }
    } catch {}
  }
  return $false
}

switch ($Mode) {
  "export" {
    if ([string]::IsNullOrWhiteSpace($PptxPath) -or [string]::IsNullOrWhiteSpace($CacheDir)) {
      throw "Export mode expects PptxPath and CacheDir."
    }

    $PptxPath = Normalize-PPTBridgeFilePath $PptxPath
    $slidesDir = Join-Path $CacheDir "slides"
    New-Item -ItemType Directory -Force -Path $slidesDir | Out-Null
    Get-ChildItem -LiteralPath $slidesDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $archive = $null
    $app = $null
    $presentation = $null
    $ownsPresentation = $false
    try {
      $archive = Open-PPTBridgeZipArchive $PptxPath
      $slideEntries = @()
      $slideSize = [pscustomobject]@{ Width = 0.0; Height = 0.0 }
      if ($null -ne $archive) {
        $slideEntries = Get-PPTBridgeSlideEntries $archive
        $slideSize = Get-PPTBridgeSlideSize $archive
      }
      $extractedMediaCache = @{}

      $app = New-Object -ComObject PowerPoint.Application
      Set-PPTBridgePowerPointVisible $app
      $presentation = Find-PPTBridgePresentation $app $PptxPath
      if ($null -eq $presentation) {
        $presentation = $app.Presentations.Open($PptxPath, $false, $false, $false)
        $ownsPresentation = $true
      }
      $presentation.Export($slidesDir, "PNG", $Width, $Height)
      $slideCount = [int]$presentation.Slides.Count
      $exportedSlideFiles = @(Wait-PPTBridgeExportedImageFiles $slidesDir $slideCount)

      Write-Output "OK"
      Write-Output ("COUNT|{0}" -f $slideCount)
      $slideAspect = 0.0
      try {
        $slideWidth = [double]$presentation.PageSetup.SlideWidth
        $slideHeight = [double]$presentation.PageSetup.SlideHeight
        if ($slideWidth -gt 0.0 -and $slideHeight -gt 0.0) {
          $slideAspect = $slideWidth / $slideHeight
        }
      } catch {}
      Write-Output ("ASPECT|" + $slideAspect.ToString("R", [Globalization.CultureInfo]::InvariantCulture))
      Write-Output ("MEDIA_SCAN|{0}" -f $(if ($SkipEmbeddedMedia) { "0" } else { "1" }))

      foreach ($slide in @($presentation.Slides)) {
        $index = [int]$slide.SlideIndex
        $file = Resolve-PPTBridgeExportedSlideFile $exportedSlideFiles $index
        if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file)) {
          $available = (($exportedSlideFiles | ForEach-Object { $_.Name }) -join ", ")
          throw ("PowerPoint did not export a readable slide image for slide {0}. Exported files: {1}" -f $index, $available)
        }

        $title = ""
        try { $title = [string]$slide.Name } catch {}
        $notes = Get-PPTBridgeNotes $slide
        Write-Output ("SLIDE|{0}|{1}|{2}|{3}" -f
          $index,
          (Escape-PPTBridgeValue $file),
          (Escape-PPTBridgeValue $title),
          (Escape-PPTBridgeValue $notes))

        if (-not $SkipEmbeddedMedia -and $null -ne $archive -and $index -le $slideEntries.Count) {
          foreach ($media in @(Get-PPTBridgeMediaForSlide $archive $slideEntries[$index - 1] $CacheDir $slideSize.Width $slideSize.Height $extractedMediaCache)) {
            Write-Output ("MEDIA|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}" -f
              $index,
              [string]$media.Kind,
              (Escape-PPTBridgeValue ([string]$media.FilePath)),
              (Escape-PPTBridgeValue ([string]$media.OriginalEntry)),
              [string]$media.X,
              [string]$media.Y,
              [string]$media.Width,
              [string]$media.Height,
              ($(if ($media.Autoplay) { "1" } else { "0" })),
              ($(if ($media.Loop) { "1" } else { "0" })))
          }
        }
      }
    } finally {
      if ($null -ne $archive) { $archive.Dispose() }
      if ($ownsPresentation -and $null -ne $presentation) {
        try { $presentation.Close() } catch {}
      }
      if ($null -ne $app) {
        $canQuit = $false
        try {
          $canQuit = [int]$app.Presentations.Count -eq 0 -and [int]$app.SlideShowWindows.Count -eq 0
        } catch {}
        if ($canQuit) {
          try { $app.Quit() } catch {}
        }
      }
    }
  }

  "live-start" {
    if ([string]::IsNullOrWhiteSpace($PptxPath)) {
      throw "live-start expects PptxPath."
    }

    $app = Get-PPTBridgeApp $true
    Set-PPTBridgePowerPointVisible $app
    $presentation = Open-PPTBridgePresentation $app $PptxPath $true
    $window = Get-PPTBridgeWindow $app $presentation
    if ($null -eq $window) {
      try { $presentation.SlideShowSettings.ShowType = 2 } catch {}
      try { $presentation.SlideShowSettings.LoopUntilStopped = $false } catch {}
      $null = $presentation.SlideShowSettings.Run()
      Start-Sleep -Milliseconds 700
      $window = Get-PPTBridgeWindow $app $presentation
    }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "live-state" {
    $app = Get-PPTBridgeApp $false
    if ($null -eq $app) {
      Emit-PPTBridgeSnapshot $null $null
      return
    }

    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "live-stop" {
    $app = Get-PPTBridgeApp $false
    if ($null -eq $app) {
      Emit-PPTBridgeSnapshot $null $null
      return
    }

    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) {
      try { $window.View.Exit() } catch {}
      Start-Sleep -Milliseconds 250
    }
    $window = Get-PPTBridgeWindow $app $presentation
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "next" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window -and $presentation) {
      $current = 0
      $count = 0
      $clickIndex = 0
      $clickCount = 0
      try { $current = [int]$window.View.CurrentShowPosition } catch {}
      try { $count = [int]$presentation.Slides.Count } catch {}
      try { $clickIndex = [int]$window.View.GetClickIndex() } catch {}
      try { $clickCount = [int]$window.View.GetClickCount() } catch {}
      $mediaStarted = $false
      if ($clickIndex -ge $clickCount) {
        $mediaStarted = Start-PPTBridgePendingMedia $window $presentation
      }
      if (-not $mediaStarted -and ($count -le 0 -or $current -lt $count -or $clickIndex -lt $clickCount)) {
        $window.View.Next()
      }
    }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "previous" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) {
      $current = 0
      try { $current = [int]$window.View.CurrentShowPosition } catch {}
      if ($current -gt 1) {
        $window.View.Previous()
      }
    }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "first" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) { $window.View.GotoSlide(1) }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "last" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window -and $presentation) { $window.View.GotoSlide([int]$presentation.Slides.Count) }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "goto" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) { $window.View.GotoSlide($TargetSlide) }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  default {
    throw "Unsupported PPTBridge mode: $Mode"
  }
}
)POWERSHELL";
  return script;
}

fs::path EnsurePowerShellScript()
{
  const fs::path script_dir = PluginCacheRoot() / L"scripts";
  const fs::path script_path = script_dir / L"pptbridge-windows.ps1";
  const auto script_contents = BuildWindowsPowerShellScript();
  const auto existing = ReadUtf8File(script_path);
  if (existing != script_contents) {
    WriteUtf8File(script_path, script_contents);
  }
  return script_path;
}

bool RunPowerShellMode(
  const std::wstring &mode,
  const std::wstring &pptx_path,
  const std::wstring &cache_dir,
  int target_slide,
  std::string &out_stdout,
  int &out_exit_code,
  bool skip_embedded_media = false)
{
  const auto script_path = EnsurePowerShellScript();
  std::vector<std::wstring> args = {
    kPowerShellExe,
    L"-NoLogo",
    L"-NoProfile",
    L"-ExecutionPolicy",
    L"Bypass",
    L"-File",
    script_path.wstring(),
    L"-Mode",
    mode
  };

  if (!pptx_path.empty()) {
    args.push_back(L"-PptxPath");
    args.push_back(pptx_path);
  }
  if (!cache_dir.empty()) {
    args.push_back(L"-CacheDir");
    args.push_back(cache_dir);
  }
  if (target_slide > 0) {
    args.push_back(L"-TargetSlide");
    args.push_back(std::to_wstring(target_slide));
  }

  DWORD timeout_ms = kLiveCommandProcessTimeoutMs;
  if (mode == L"export") {
    timeout_ms = kExportProcessTimeoutMs;
  } else if (mode == L"live-start") {
    timeout_ms = kLiveStartProcessTimeoutMs;
  } else if (mode == L"live-stop") {
    timeout_ms = kLiveStopProcessTimeoutMs;
  }
  if (skip_embedded_media) {
    args.push_back(L"-SkipEmbeddedMedia");
  }

  return RunProcessCapture(args, timeout_ms, out_stdout, out_exit_code);
}

bool ParseExportOutput(const std::string &output, ParsedDeckData &out_deck, std::string &out_error)
{
  out_deck = {};
  bool ok = false;
  for (const auto &line : SplitLines(output)) {
    if (line == "OK") {
      ok = true;
      continue;
    }

    if (line.rfind("ASPECT|", 0) == 0) {
      try {
        out_deck.slide_aspect_ratio = std::stod(line.substr(7));
      } catch (...) {
        out_deck.slide_aspect_ratio = 0.0;
      }
      continue;
    }

    if (line.rfind("MEDIA_SCAN|", 0) == 0) {
      out_deck.media_scan_complete = line.substr(11) != "0";
      continue;
    }

    if (line.rfind("SLIDE|", 0) != 0) {
      continue;
    }

    const auto parts = SplitPipeLine(line);
    if (parts.size() < 5) {
      continue;
    }

    CachedSlide slide;
    slide.image_path = Utf8ToWide(parts[2]);
    slide.meta.title = parts[3];
    slide.meta.notes = parts[4];
    out_deck.slides.push_back(std::move(slide));
    if (out_deck.media_by_slide.size() < out_deck.slides.size()) {
      out_deck.media_by_slide.resize(out_deck.slides.size());
    }
  }

  for (const auto &line : SplitLines(output)) {
    if (line.rfind("MEDIA|", 0) != 0) {
      continue;
    }

    const auto parts = SplitPipeLine(line);
    if (parts.size() < 10) {
      continue;
    }

    size_t slide_index = 0;
    try {
      slide_index = static_cast<size_t>(std::stoul(parts[1]));
    } catch (...) {
      continue;
    }
    if (slide_index == 0) {
      continue;
    }

    if (out_deck.media_by_slide.size() < slide_index) {
      out_deck.media_by_slide.resize(slide_index);
    }

    EmbeddedMedia media;
    media.kind = parts[2] == "audio" ? EmbeddedMediaKind::Audio : EmbeddedMediaKind::Video;
    media.file_path = parts[3];
    media.original_entry = parts[4];
    try {
      media.x = std::stod(parts[5]);
      media.y = std::stod(parts[6]);
      media.width = std::stod(parts[7]);
      media.height = std::stod(parts[8]);
    } catch (...) {
      continue;
    }
    media.autoplay = parts[9] != "0";
    media.loop = parts.size() > 10 && parts[10] == "1";
    out_deck.media_by_slide[slide_index - 1].push_back(std::move(media));
  }

  if (!ok || out_deck.slides.empty() || out_deck.slide_aspect_ratio < 0.2 || out_deck.slide_aspect_ratio > 10.0) {
    out_error = output.empty() ? "PowerPoint export produced no usable slide output." : output;
    return false;
  }

  if (!CachedSlideImagesExist(out_deck.slides)) {
    out_error = "PowerPoint export completed, but the exported slide image files were not found.";
    return false;
  }

  if (out_deck.media_by_slide.size() < out_deck.slides.size()) {
    out_deck.media_by_slide.resize(out_deck.slides.size());
  }

  return true;
}

bool ParseLiveSnapshot(const std::string &output, LiveSnapshot &snapshot, std::string &out_error)
{
  snapshot = {};
  bool ok = false;
  for (const auto &line : SplitLines(output)) {
    if (line == "OK") {
      ok = true;
      continue;
    }

    if (line.rfind("RUNNING|", 0) == 0) {
      snapshot.running = line.substr(8) == "1";
      continue;
    }
    if (line.rfind("SLIDE|", 0) == 0) {
      try {
        snapshot.current_slide = static_cast<size_t>(std::max(0, std::stoi(line.substr(6))));
      } catch (...) {
      }
      continue;
    }
    if (line.rfind("COUNT|", 0) == 0) {
      try {
        snapshot.slide_count = static_cast<size_t>(std::max(0, std::stoi(line.substr(6))));
      } catch (...) {
      }
      continue;
    }
    if (line.rfind("TITLE|", 0) == 0) {
      snapshot.presentation_title = UnescapePipeValue(line.substr(6));
      continue;
    }
    if (line.rfind("WINDOW|", 0) == 0) {
      snapshot.window_title = UnescapePipeValue(line.substr(7));
      continue;
    }
    if (line.rfind("ASPECT|", 0) == 0) {
      try {
        snapshot.slide_aspect_ratio = std::stod(line.substr(7));
      } catch (...) {
        snapshot.slide_aspect_ratio = 0.0;
      }
      continue;
    }
  }

  if (!ok) {
    out_error = output.empty() ? "PowerPoint live command did not return a valid response." : output;
    return false;
  }

  return true;
}

class GdiPlusScope {
public:
  GdiPlusScope()
  {
    GdiplusStartupInput input;
    GdiplusStartup(&token_, &input, nullptr);
  }

  ~GdiPlusScope()
  {
    if (token_ != 0) {
      GdiplusShutdown(token_);
    }
  }

private:
  ULONG_PTR token_ = 0;
};

GdiPlusScope &GlobalGdiPlus()
{
  static GdiPlusScope scope;
  return scope;
}

RectF FitRect(float container_x, float container_y, float container_width, float container_height, float image_width, float image_height)
{
  if (image_width <= 0.0f || image_height <= 0.0f) {
    return RectF(container_x, container_y, container_width, container_height);
  }

  const float container_ratio = container_width / container_height;
  const float image_ratio = image_width / image_height;

  float draw_width = container_width;
  float draw_height = container_height;
  float draw_x = container_x;
  float draw_y = container_y;

  if (image_ratio > container_ratio) {
    draw_height = container_width / image_ratio;
    draw_y = container_y + ((container_height - draw_height) * 0.5f);
  } else {
    draw_width = container_height * image_ratio;
    draw_x = container_x + ((container_width - draw_width) * 0.5f);
  }

  return RectF(draw_x, draw_y, draw_width, draw_height);
}

RectF AspectFillRect(float container_x, float container_y, float container_width, float container_height, float image_width, float image_height)
{
  if (image_width <= 0.0f || image_height <= 0.0f) {
    return RectF(container_x, container_y, container_width, container_height);
  }

  const float scale = std::max(container_width / image_width, container_height / image_height);
  const float draw_width = image_width * scale;
  const float draw_height = image_height * scale;
  return RectF(
    container_x + ((container_width - draw_width) * 0.5f),
    container_y + ((container_height - draw_height) * 0.5f),
    draw_width,
    draw_height);
}

float ClampFloat(float value, float minimum, float maximum)
{
  return std::min(std::max(value, minimum), maximum);
}

void SplitVerticalPanelHeights(
  float available_height,
  float gap,
  float notes_ratio,
  float &next_height,
  float &notes_height)
{
  const float panel_height = std::max(1.0f, available_height - gap);
  const float min_next = std::min(90.0f, panel_height * 0.45f);
  const float min_notes = std::min(80.0f, std::max(0.0f, panel_height - min_next));
  notes_height = ClampFloat(panel_height * notes_ratio, min_notes, panel_height - min_next);
  next_height = panel_height - notes_height;
}

void SplitConfidenceHeights(
  float available_height,
  float gap,
  float strip_ratio,
  float &preview_height,
  float &strip_height)
{
  const float panel_height = std::max(1.0f, available_height - gap);
  const float min_strip = std::min(112.0f, panel_height * 0.30f);
  const float max_strip = std::max(min_strip, panel_height * 0.42f);
  strip_height = ClampFloat(available_height * 0.22f * strip_ratio, min_strip, max_strip);
  preview_height = panel_height - strip_height;
}

RectF PositionedPreviewRect(const RectF &container, float image_width, float image_height, const PresenterRenderOptions &options)
{
  if (image_width <= 0.0f || image_height <= 0.0f || container.Width <= 0.0f || container.Height <= 0.0f) {
    return container;
  }

  const float fit_scale = std::min(container.Width / image_width, container.Height / image_height);
  const float fill_scale = std::max(container.Width / image_width, container.Height / image_height);
  float scale = options.preview_scale_mode == PresenterPreviewScaleMode::Fit ? fit_scale : fill_scale;
  float user_scale = ClampFloat(static_cast<float>(options.preview_scale_percent) / 100.0f, 0.25f, 3.0f);
  if (options.preview_scale_mode == PresenterPreviewScaleMode::Crop) {
    user_scale = std::max(1.0f, user_scale);
  }
  scale *= user_scale;

  const float draw_width = image_width * scale;
  const float draw_height = image_height * scale;
  const float x_weight = (ClampFloat(static_cast<float>(options.preview_position_x), -100.0f, 100.0f) + 100.0f) / 200.0f;
  const float y_weight = (ClampFloat(static_cast<float>(options.preview_position_y), -100.0f, 100.0f) + 100.0f) / 200.0f;
  return RectF(
    container.X + ((container.Width - draw_width) * x_weight),
    container.Y + ((container.Height - draw_height) * y_weight),
    draw_width,
    draw_height);
}

void DrawCenteredMessage(Graphics &graphics, uint32_t width, uint32_t height, const std::wstring &title, const std::wstring &subtitle)
{
  SolidBrush background(Color(255, 11, 14, 20));
  graphics.FillRectangle(&background, 0, 0, width, height);

  SolidBrush accent(Color(255, 84, 226, 170));
  graphics.FillRectangle(&accent, 0, 0, width, 6);

  Font title_font(L"Segoe UI Semibold", 42.0f, FontStyleBold, UnitPixel);
  Font subtitle_font(L"Segoe UI", 22.0f, FontStyleRegular, UnitPixel);
  SolidBrush text_brush(Color(255, 241, 243, 248));
  SolidBrush sub_brush(Color(255, 183, 188, 203));
  StringFormat centered;
  centered.SetAlignment(StringAlignmentCenter);
  centered.SetLineAlignment(StringAlignmentCenter);

  RectF title_rect(0.0f, (height * 0.5f) - 80.0f, static_cast<REAL>(width), 60.0f);
  RectF subtitle_rect(120.0f, (height * 0.5f) - 5.0f, static_cast<REAL>(width - 240), 120.0f);
  graphics.DrawString(title.c_str(), -1, &title_font, title_rect, &centered, &text_brush);
  graphics.DrawString(subtitle.c_str(), -1, &subtitle_font, subtitle_rect, &centered, &sub_brush);
}

bool CopyBitmapToBGRA(Bitmap &bitmap, std::vector<uint8_t> &out_pixels, uint32_t &out_stride)
{
  Rect rect(0, 0, static_cast<INT>(bitmap.GetWidth()), static_cast<INT>(bitmap.GetHeight()));
  BitmapData data = {};
  if (bitmap.LockBits(&rect, ImageLockModeRead, PixelFormat32bppARGB, &data) != Ok) {
    return false;
  }

  out_stride = static_cast<uint32_t>(bitmap.GetWidth() * 4);
  out_pixels.resize(static_cast<size_t>(bitmap.GetHeight()) * out_stride);
  const auto *source = static_cast<const uint8_t *>(data.Scan0);
  for (uint32_t row = 0; row < bitmap.GetHeight(); ++row) {
    std::memcpy(
      out_pixels.data() + (static_cast<size_t>(row) * out_stride),
      source + (static_cast<size_t>(row) * static_cast<size_t>(data.Stride)),
      out_stride);
  }

  bitmap.UnlockBits(&data);
  return true;
}

bool DrawImageFile(Graphics &graphics, const std::wstring &path, const RectF &destination)
{
  if (path.empty() || !fs::exists(fs::path(path))) {
    return false;
  }

  Bitmap image(path.c_str());
  if (image.GetLastStatus() != Ok || image.GetWidth() == 0 || image.GetHeight() == 0) {
    return false;
  }

  const auto draw_rect = FitRect(destination.X, destination.Y, destination.Width, destination.Height,
                                 static_cast<float>(image.GetWidth()), static_cast<float>(image.GetHeight()));
  graphics.DrawImage(&image, draw_rect);
  return true;
}

Color ColorFromRgb(uint32_t color, BYTE alpha = 255)
{
  return Color(
    alpha,
    static_cast<BYTE>((color >> 16) & 0xff),
    static_cast<BYTE>((color >> 8) & 0xff),
    static_cast<BYTE>(color & 0xff));
}

RectF PresenterBackgroundImageRect(Bitmap &image, const RectF &canvas, const PresenterRenderOptions &options)
{
  const float image_width = static_cast<float>(image.GetWidth());
  const float image_height = static_cast<float>(image.GetHeight());
  if (image_width <= 0.0f || image_height <= 0.0f) {
    return RectF();
  }

  if (options.background_image_mode == PresenterBackgroundImageMode::Fill) {
    return AspectFillRect(canvas.X, canvas.Y, canvas.Width, canvas.Height, image_width, image_height);
  }
  if (options.background_image_mode == PresenterBackgroundImageMode::Fit) {
    const RectF inset(canvas.X + 32.0f, canvas.Y + 32.0f, std::max(1.0f, canvas.Width - 64.0f), std::max(1.0f, canvas.Height - 64.0f));
    return FitRect(inset.X, inset.Y, inset.Width, inset.Height, image_width, image_height);
  }

  const float max_width = std::max(120.0f, canvas.Width * 0.24f);
  const float max_height = std::max(90.0f, canvas.Height * 0.20f);
  const RectF watermark(
    canvas.X + canvas.Width - max_width - 28.0f,
    canvas.Y + canvas.Height - max_height - 24.0f,
    max_width,
    max_height);
  return FitRect(watermark.X, watermark.Y, watermark.Width, watermark.Height, image_width, image_height);
}

void DrawPresenterBackgroundImage(Graphics &graphics, const RectF &canvas, const PresenterRenderOptions &options)
{
  if (options.background_image_path.empty()) {
    return;
  }

  const auto opacity =
    static_cast<BYTE>(std::round(ClampFloat(static_cast<float>(options.background_image_opacity_percent) / 100.0f, 0.0f, 1.0f) * 255.0f));
  if (opacity == 0) {
    return;
  }

  const std::wstring image_path = Utf8ToWide(options.background_image_path);
  if (image_path.empty() || !fs::exists(fs::path(image_path))) {
    return;
  }

  Bitmap image(image_path.c_str());
  if (image.GetLastStatus() != Ok || image.GetWidth() == 0 || image.GetHeight() == 0) {
    return;
  }

  const RectF destination = PresenterBackgroundImageRect(image, canvas, options);
  if (destination.Width <= 0.0f || destination.Height <= 0.0f) {
    return;
  }

  ImageAttributes attributes;
  ColorMatrix matrix = {
    1.0f, 0.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 0.0f, static_cast<REAL>(opacity) / 255.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 0.0f, 1.0f,
  };
  attributes.SetColorMatrix(&matrix, ColorMatrixFlagsDefault, ColorAdjustTypeBitmap);

  Region previous_clip;
  graphics.GetClip(&previous_clip);
  graphics.SetClip(canvas);
  graphics.DrawImage(
    &image,
    destination,
    0.0f,
    0.0f,
    static_cast<REAL>(image.GetWidth()),
    static_cast<REAL>(image.GetHeight()),
    UnitPixel,
    &attributes);
  graphics.SetClip(&previous_clip, CombineModeReplace);
}

bool DrawImagePreview(Graphics &graphics, const std::wstring &path, const RectF &destination, const PresenterRenderOptions &options)
{
  if (path.empty() || !fs::exists(fs::path(path))) {
    return false;
  }

  Bitmap image(path.c_str());
  if (image.GetLastStatus() != Ok || image.GetWidth() == 0 || image.GetHeight() == 0) {
    return false;
  }

  const auto draw_rect = PositionedPreviewRect(
    destination,
    static_cast<float>(image.GetWidth()),
    static_cast<float>(image.GetHeight()),
    options);

  Region previous_clip;
  graphics.GetClip(&previous_clip);
  graphics.SetClip(destination);
  graphics.DrawImage(&image, draw_rect);
  graphics.SetClip(&previous_clip, CombineModeReplace);
  return true;
}

std::string CueTitleForSlide(const std::vector<CachedSlide> &slides, std::size_t index)
{
  if (index < slides.size()) {
    const std::string title = TrimWhitespaceCopy(slides[index].meta.title);
    if (!title.empty()) {
      return title;
    }
  }
  return "Slide " + std::to_string(index + 1);
}

void DrawCueList(
  Graphics &graphics,
  const std::vector<CachedSlide> &slides,
  const std::set<std::size_t> &checked_cues,
  std::size_t current,
  std::size_t slide_count,
  const RectF &cue_box)
{
  SolidBrush cue_fill(Color(245, 18, 24, 32));
  SolidBrush title_brush(Color(255, 199, 206, 220));
  SolidBrush body_brush(Color(255, 210, 216, 228));
  SolidBrush accent_brush(Color(255, 84, 226, 170));
  graphics.FillRectangle(&cue_fill, cue_box);

  Font label_font(L"Segoe UI Semibold", 13.0f, FontStyleBold, UnitPixel);
  Font line_font(L"Consolas", 12.0f, FontStyleRegular, UnitPixel);
  graphics.DrawString(L"Cue List", -1, &label_font, PointF(cue_box.X + 14.0f, cue_box.Y + 10.0f), &title_brush);

  const std::size_t count = std::max<std::size_t>(slide_count, slides.size());
  if (count == 0) {
    graphics.DrawString(L"No cues available yet", -1, &line_font, PointF(cue_box.X + 14.0f, cue_box.Y + 38.0f), &body_brush);
    return;
  }

  const std::size_t start = current > 1 ? current - 1 : 0;
  const std::size_t end = std::min<std::size_t>(count, start + 5);
  float y = cue_box.Y + 36.0f;
  for (std::size_t index = start; index < end && y < cue_box.Y + cue_box.Height - 10.0f; ++index) {
    const bool is_current = index == current;
    const bool is_next = index == current + 1;
    const bool checked = checked_cues.find(index) != checked_cues.end();
    std::ostringstream line;
    line << (is_current ? "> " : "  ");
    line << (checked ? "[x] " : "[ ] ");
    if (index + 1 < 10) {
      line << "0";
    }
    line << (index + 1) << "  " << CueTitleForSlide(slides, index);
    if (is_next) {
      line << "  next";
    }
    const std::wstring wide_line = Utf8ToWide(line.str());
    graphics.DrawString(
      wide_line.c_str(),
      -1,
      &line_font,
      RectF(cue_box.X + 14.0f, y, std::max(1.0f, cue_box.Width - 28.0f), 18.0f),
      nullptr,
      is_current ? &accent_brush : &body_brush);
    y += 20.0f;
  }
}

std::wstring FormatDuration(uint64_t seconds)
{
  const uint64_t hours = seconds / 3600;
  const uint64_t minutes = (seconds % 3600) / 60;
  const uint64_t remaining = seconds % 60;
  wchar_t buffer[64] = {};
  if (hours > 0) {
    swprintf(buffer, 64, L"%llu:%02llu:%02llu",
             static_cast<unsigned long long>(hours),
             static_cast<unsigned long long>(minutes),
             static_cast<unsigned long long>(remaining));
  } else {
    swprintf(buffer, 64, L"%02llu:%02llu",
             static_cast<unsigned long long>(minutes),
             static_cast<unsigned long long>(remaining));
  }
  return buffer;
}

}  // namespace

struct PresentationDocument::Impl {
  explicit Impl(std::string pptx_path_)
    : path(std::move(pptx_path_)),
      name(WideToUtf8(fs::path(Utf8ToWide(path)).filename().wstring())),
      cache_root(CacheRootForDeck(path)),
      metadata_path(cache_root / L"slides-metadata.txt"),
      file_stamp(CurrentFileStamp(fs::path(Utf8ToWide(path))))
  {
  }

  std::mutex mutex;
  std::mutex script_mutex;
  mutable std::mutex render_mutex;
  std::string path;
  std::string name;
  fs::path cache_root;
  fs::path metadata_path;
  std::string file_stamp;
  std::vector<CachedSlide> slides;
  std::set<std::size_t> checked_cues;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  double slide_aspect_ratio = 16.0 / 9.0;
  size_t current_index = 0;
  bool current_media_triggered = false;
  bool loaded = false;
  bool loading = false;
  bool load_requested = true;
  bool force_reload = false;
  bool active_force_reload = false;
  bool black_screen = false;
  bool live_enabled = true;
  bool live_auto_start = false;
  bool live_start_requested = false;
  uint64_t live_request_generation = 0;
  bool live_ready = false;
  bool presenter_assets_wanted = false;
  std::string live_window_title;
  std::string last_error;
  uint64_t state_version = 1;
  std::chrono::steady_clock::time_point timer_started_at = std::chrono::steady_clock::time_point::min();
  std::chrono::steady_clock::time_point live_last_sync = std::chrono::steady_clock::time_point::min();
  bool live_sync_inflight = false;
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
  return impl_->name;
}

void PresentationDocument::SetLivePowerPointEnabled(bool enabled)
{
  bool should_start = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->live_enabled == enabled) {
      return;
    }

    impl_->live_enabled = enabled;
    impl_->live_request_generation += 1;
    impl_->last_error.clear();
    if (enabled && impl_->live_auto_start && !impl_->live_ready) {
      impl_->live_start_requested = true;
      impl_->load_requested = true;
      should_start = true;
    }
    if (!enabled) {
      impl_->live_start_requested = false;
      impl_->live_ready = false;
      impl_->live_window_title.clear();
      impl_->current_media_triggered = false;
    }
    impl_->state_version += 1;
  }

  if (should_start) {
    StartLoadIfNeeded(false);
  }
}

void PresentationDocument::SetLivePowerPointAutoStart(bool enabled)
{
  bool should_start = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->live_auto_start == enabled) {
      return;
    }

    impl_->live_auto_start = enabled;
    if (enabled && impl_->live_enabled && !impl_->live_ready) {
      impl_->live_start_requested = true;
      impl_->load_requested = true;
      impl_->live_request_generation += 1;
      should_start = true;
    } else if (!enabled && !impl_->live_ready) {
      impl_->live_start_requested = false;
      impl_->live_request_generation += 1;
    }
    impl_->state_version += 1;
  }

  if (should_start) {
    StartLoadIfNeeded(false);
  }
}

bool PresentationDocument::IsLivePowerPointEnabled() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_enabled;
}

bool PresentationDocument::IsLivePowerPointReady() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_enabled && impl_->live_ready;
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
    if (!IsSupportedPowerPointExtension(impl_->path)) {
      impl_->live_enabled = false;
      impl_->live_start_requested = false;
      impl_->live_request_generation += 1;
      impl_->last_error = "Windows live mode expects a PowerPoint file such as .ppt, .pptx, .pptm, .ppsx, .potx, or .potm.";
      impl_->state_version += 1;
      return;
    }

    impl_->live_enabled = true;
    impl_->live_start_requested = true;
    impl_->live_request_generation += 1;
    impl_->live_ready = false;
    impl_->live_window_title.clear();
    impl_->black_screen = false;
    impl_->current_media_triggered = false;
    impl_->load_requested = true;
    impl_->live_last_sync = std::chrono::steady_clock::time_point::min();
    impl_->last_error.clear();
    impl_->state_version += 1;
  }

  StartLoadIfNeeded(false);
}

void PresentationDocument::StopLivePowerPoint()
{
  uint64_t request_generation = 0;
  std::string cache_dir;
  std::string presentation_path;
  std::string window_title;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->live_start_requested = false;
    impl_->live_ready = false;
    request_generation = ++impl_->live_request_generation;
    cache_dir = WideToUtf8(impl_->cache_root.wstring());
    presentation_path = impl_->path;
    window_title = impl_->live_window_title;
    impl_->live_window_title.clear();
    impl_->current_media_triggered = false;
    impl_->black_screen = false;
    impl_->state_version += 1;
  }

  StopLivePowerPointOnLiveQueue(
    request_generation,
    std::move(cache_dir),
    std::move(presentation_path),
    std::move(window_title));
}

void PresentationDocument::StopLivePowerPointOnLiveQueue(
  uint64_t request_generation,
  std::string cache_dir,
  std::string presentation_path,
  std::string window_title)
{
  std::string output;
  int exit_code = -1;
  LiveSnapshot snapshot;
  std::string error;
  bool ran_command = false;

  {
    std::lock_guard<std::mutex> script_lock(impl_->script_mutex);
    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      if (impl_->live_request_generation != request_generation || impl_->live_start_requested) {
        return;
      }
    }

    ran_command = RunPowerShellMode(
      L"live-stop",
      Utf8ToWide(presentation_path),
      Utf8ToWide(cache_dir),
      0,
      output,
      exit_code);
  }

  const bool parsed = ParseLiveSnapshot(output, snapshot, error);
  const bool stopped = ran_command && exit_code == 0 && parsed && !snapshot.running;

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->live_request_generation != request_generation || impl_->live_start_requested) {
    return;
  }
  impl_->live_ready = false;
  impl_->live_window_title.clear();
  impl_->current_media_triggered = false;
  if (stopped) {
    impl_->last_error.clear();
    blog(
      LOG_INFO,
      "[PPTBridge SK] Windows PowerPoint live slideshow stopped for '%s'%s%s%s",
      impl_->path.c_str(),
      window_title.empty() ? "" : " (",
      window_title.empty() ? "" : window_title.c_str(),
      window_title.empty() ? "" : ")");
  } else {
    impl_->last_error = error.empty() ? output : error;
    if (impl_->last_error.empty()) {
      impl_->last_error = "PowerPoint live slideshow stop did not return a clean status.";
    }
    blog(LOG_WARNING,
      "[PPTBridge SK] Windows PowerPoint live slideshow stop failed for '%s': %s",
      impl_->path.c_str(),
      impl_->last_error.c_str());
  }
  impl_->state_version += 1;
}

void PresentationDocument::StopLivePowerPointAsync()
{
  uint64_t request_generation = 0;
  std::string cache_dir;
  std::string presentation_path;
  std::string window_title;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->live_start_requested = false;
    impl_->live_ready = false;
    request_generation = ++impl_->live_request_generation;
    cache_dir = WideToUtf8(impl_->cache_root.wstring());
    presentation_path = impl_->path;
    window_title = impl_->live_window_title;
    impl_->live_window_title.clear();
    impl_->current_media_triggered = false;
    impl_->black_screen = false;
    impl_->state_version += 1;
  }

  auto self = shared_from_this();
  std::thread([self, request_generation, cache_dir, presentation_path, window_title]() {
    self->StopLivePowerPointOnLiveQueue(
      request_generation,
      cache_dir,
      presentation_path,
      window_title);
  }).detach();
}

void PresentationDocument::SyncLiveStateAsync()
{
  uint64_t request_generation = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->live_enabled || !impl_->live_start_requested ||
        (!impl_->loaded && !impl_->live_ready) || impl_->live_sync_inflight) {
      return;
    }
    const auto now = std::chrono::steady_clock::now();
    if (impl_->live_last_sync != std::chrono::steady_clock::time_point::min() &&
        now - impl_->live_last_sync < std::chrono::milliseconds(180)) {
      return;
    }
    request_generation = impl_->live_request_generation;
    impl_->live_sync_inflight = true;
  }

  auto self = shared_from_this();
  std::thread([self, request_generation]() {
    LiveSnapshot snapshot;
    std::string error;
    std::string output;
    int exit_code = -1;

    {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      {
        std::lock_guard<std::mutex> lock(self->impl_->mutex);
        if (!self->impl_->live_enabled || !self->impl_->live_start_requested ||
            self->impl_->live_request_generation != request_generation) {
          self->impl_->live_sync_inflight = false;
          return;
        }
      }
      RunPowerShellMode(
        L"live-state",
        Utf8ToWide(self->impl_->path),
        self->impl_->cache_root.wstring(),
        0,
        output,
        exit_code);
    }

    const bool parsed = exit_code == 0 && ParseLiveSnapshot(output, snapshot, error);
    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    self->impl_->live_sync_inflight = false;
    self->impl_->live_last_sync = std::chrono::steady_clock::now();
    if (!self->impl_->live_enabled || !self->impl_->live_start_requested ||
        self->impl_->live_request_generation != request_generation) {
      return;
    }

    if (parsed && snapshot.running) {
      bool changed = false;
      if (self->impl_->live_ready != snapshot.running) {
        self->impl_->live_ready = snapshot.running;
        changed = true;
      }
      if (snapshot.slide_count > 0) {
        const auto next_index = std::min(
          snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
          snapshot.slide_count - 1);
        if (self->impl_->current_index != next_index) {
          self->impl_->current_index = next_index;
          changed = true;
        }
      }
      if (!snapshot.window_title.empty() && self->impl_->live_window_title != snapshot.window_title) {
        self->impl_->live_window_title = snapshot.window_title;
        changed = true;
      } else if (!snapshot.running && !self->impl_->live_window_title.empty()) {
        self->impl_->live_window_title.clear();
        changed = true;
      }
      if (snapshot.slide_aspect_ratio >= 0.2 && snapshot.slide_aspect_ratio <= 10.0 &&
          self->impl_->slide_aspect_ratio != snapshot.slide_aspect_ratio) {
        self->impl_->slide_aspect_ratio = snapshot.slide_aspect_ratio;
        changed = true;
      }
      if (snapshot.running && self->impl_->timer_started_at == std::chrono::steady_clock::time_point::min()) {
        self->impl_->timer_started_at = std::chrono::steady_clock::now();
        changed = true;
      }
      if (snapshot.running && self->impl_->current_media_triggered) {
        self->impl_->current_media_triggered = false;
        changed = true;
      }
      if (!self->impl_->last_error.empty()) {
        self->impl_->last_error.clear();
        changed = true;
      }
      if (changed) {
        self->impl_->state_version += 1;
      }
    } else {
      const std::string detail = parsed && !snapshot.running
        ? "The PowerPoint slideshow was closed."
        : (!error.empty() ? error : output);
      const std::string message = LiveRecoveryErrorMessage(detail);
      if (self->impl_->live_ready || !self->impl_->live_window_title.empty() || self->impl_->last_error != message) {
        self->impl_->live_ready = false;
        self->impl_->live_window_title.clear();
        self->impl_->last_error = message;
        self->impl_->state_version += 1;
      }
    }
  }).detach();
}

void PresentationDocument::SetPresenterAssetsWanted(bool wanted)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->presenter_assets_wanted = wanted;
}

void PresentationDocument::EnsureLoadingAsync()
{
  StartLoadIfNeeded(false);
}

void PresentationDocument::ReloadAsync()
{
  StartLoadIfNeeded(true);
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
  return impl_->last_error;
}

std::size_t PresentationDocument::SlideCount() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->slides.size();
}

std::size_t PresentationDocument::CurrentIndex() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->current_index;
}

bool PresentationDocument::HasNext() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->live_enabled || !impl_->live_ready) {
    const bool has_media_on_current =
      impl_->current_index < impl_->media_by_slide.size() && !impl_->media_by_slide[impl_->current_index].empty();
    if (has_media_on_current && !impl_->current_media_triggered) {
      return true;
    }
  }
  return impl_->current_index + 1 < impl_->slides.size();
}

bool PresentationDocument::HasPrevious() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->live_enabled || !impl_->live_ready) {
    if (impl_->current_media_triggered) {
      return true;
    }
  }
  return impl_->current_index > 0 && !impl_->slides.empty();
}

bool PresentationDocument::IsBlackScreen() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->black_screen;
}

void PresentationDocument::RunLivePowerPointCommandAsync(
  std::string command_line,
  bool clear_black)
{
  std::wstring mode = Utf8ToWide(command_line);
  int target_slide = 0;
  constexpr std::string_view goto_prefix = "goto:";
  if (command_line.rfind(goto_prefix.data(), 0) == 0) {
    mode = L"goto";
    try {
      target_slide = std::max(1, std::stoi(command_line.substr(goto_prefix.size())));
    } catch (...) {
      return;
    }
  }

  uint64_t request_generation = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->live_enabled || !impl_->live_ready || !impl_->live_start_requested) {
      return;
    }
    request_generation = impl_->live_request_generation;
    if (clear_black && impl_->black_screen) {
      impl_->black_screen = false;
      impl_->state_version += 1;
    }
  }

  auto self = shared_from_this();
  std::thread([self, mode, target_slide, request_generation]() {
    std::string output;
    int exit_code = -1;
    LiveSnapshot snapshot;
    std::string error;

    {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      {
        std::lock_guard<std::mutex> lock(self->impl_->mutex);
        if (!self->impl_->live_enabled || !self->impl_->live_start_requested ||
            self->impl_->live_request_generation != request_generation) {
          return;
        }
      }
      RunPowerShellMode(
        mode,
        Utf8ToWide(self->impl_->path),
        self->impl_->cache_root.wstring(),
        target_slide,
        output,
        exit_code);
    }

    const bool ok = exit_code == 0 && ParseLiveSnapshot(output, snapshot, error) && snapshot.running;
    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    if (!self->impl_->live_enabled || !self->impl_->live_start_requested ||
        self->impl_->live_request_generation != request_generation) {
      return;
    }

    if (ok) {
      if (snapshot.slide_count > 0) {
        const auto next_index = std::min(
          snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
          snapshot.slide_count - 1);
        self->impl_->current_index = next_index;
      }
      self->impl_->live_ready = true;
      self->impl_->live_window_title = snapshot.window_title;
      if (snapshot.slide_aspect_ratio >= 0.2 && snapshot.slide_aspect_ratio <= 10.0) {
        self->impl_->slide_aspect_ratio = snapshot.slide_aspect_ratio;
      }
      self->impl_->last_error.clear();
      self->impl_->current_media_triggered = false;
    } else {
      self->impl_->live_ready = false;
      self->impl_->live_window_title.clear();
      self->impl_->last_error = LiveRecoveryErrorMessage(!error.empty() ? error : output);
    }
    self->impl_->state_version += 1;
  }).detach();
}

void PresentationDocument::Next()
{
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->live_enabled && impl_->live_ready) {
      // The PowerShell command guards the final slide so PowerPoint never exits the show.
    } else {
      const bool has_media_on_current =
        impl_->current_index < impl_->media_by_slide.size() && !impl_->media_by_slide[impl_->current_index].empty();
      if (has_media_on_current && !impl_->current_media_triggered) {
        impl_->current_media_triggered = true;
        impl_->black_screen = false;
        impl_->state_version += 1;
        return;
      }

      if (impl_->current_index + 1 < impl_->slides.size()) {
        impl_->current_index += 1;
        impl_->current_media_triggered = false;
        impl_->state_version += 1;
      }
      impl_->black_screen = false;
      return;
    }
  }
  RunLivePowerPointCommandAsync("next", true);
}

void PresentationDocument::Previous()
{
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!(impl_->live_enabled && impl_->live_ready)) {
      if (impl_->current_media_triggered) {
        impl_->current_media_triggered = false;
      } else if (impl_->current_index > 0) {
        impl_->current_index -= 1;
      }
      impl_->black_screen = false;
      impl_->state_version += 1;
      return;
    }
  }
  RunLivePowerPointCommandAsync("previous", true);
}

void PresentationDocument::First()
{
  GoTo(0);
}

void PresentationDocument::Last()
{
  size_t target = 0;
  bool has_slides = false;
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_enabled && impl_->live_ready;
    has_slides = !impl_->slides.empty();
    if (has_slides) {
      target = impl_->slides.size() - 1;
    }
  }

  if (use_live) {
    RunLivePowerPointCommandAsync("last", true);
    return;
  }
  if (has_slides) {
    GoTo(target);
  }
}

void PresentationDocument::GoTo(std::size_t index)
{
  size_t clamped = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const size_t slide_count = impl_->slides.size();
    clamped = slide_count == 0 ? index : std::min(index, slide_count - 1);
    if (!(impl_->live_enabled && impl_->live_ready)) {
      if (slide_count == 0) {
        return;
      }
      impl_->current_index = clamped;
      impl_->current_media_triggered = false;
      impl_->black_screen = false;
      impl_->state_version += 1;
      return;
    }
  }
  RunLivePowerPointCommandAsync("goto:" + std::to_string(clamped + 1), true);
}

void PresentationDocument::ToggleBlackScreen()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->black_screen = !impl_->black_screen;
  impl_->state_version += 1;
}

uint64_t PresentationDocument::StateVersion() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->state_version;
}

uint64_t PresentationDocument::PresentationSeconds() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->timer_started_at == std::chrono::steady_clock::time_point::min()) {
    return 0;
  }

  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
    std::chrono::steady_clock::now() - impl_->timer_started_at).count());
}

std::vector<EmbeddedMedia> PresentationDocument::CurrentMedia() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->live_enabled && impl_->live_ready) {
    return {};
  }
  if (!impl_->loaded || !impl_->current_media_triggered || impl_->current_index >= impl_->media_by_slide.size()) {
    return {};
  }

  return impl_->media_by_slide[impl_->current_index];
}

PresentationStatus PresentationDocument::SnapshotStatus() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);

  PresentationStatus status;
  status.deck_name = impl_->name;
  status.deck_path = impl_->path;
  status.error = impl_->last_error;
  status.live_enabled = impl_->live_enabled;
  status.live_ready = impl_->live_ready;
  status.loading = impl_->loading;
  status.loaded = impl_->loaded;
  status.black_screen = impl_->black_screen;
  status.slide_aspect_ratio = impl_->slide_aspect_ratio;
  status.total_slides = impl_->slides.size();
  status.current_index = status.total_slides > 0 ? std::min(impl_->current_index, status.total_slides - 1) : 0;
  status.current_slide = status.total_slides > 0 ? status.current_index + 1 : 0;
  status.current_title = status.current_slide > 0 ? CueTitleForSlide(impl_->slides, status.current_index) : "";
  if (status.current_index + 1 < status.total_slides) {
    status.next_title = CueTitleForSlide(impl_->slides, status.current_index + 1);
  }
  status.timer_seconds = 0;
  if (impl_->timer_started_at != std::chrono::steady_clock::time_point::min()) {
    status.timer_seconds = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::steady_clock::now() - impl_->timer_started_at).count());
  }

  const std::size_t cue_count = impl_->slides.size();
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
  if (index >= impl_->slides.size()) {
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
  impl_->state_version += 1;
  return true;
}

bool PresentationDocument::ToggleCueChecked(std::size_t index)
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (index >= impl_->slides.size()) {
    return false;
  }

  auto found = impl_->checked_cues.find(index);
  if (found == impl_->checked_cues.end()) {
    impl_->checked_cues.insert(index);
  } else {
    impl_->checked_cues.erase(found);
  }
  impl_->state_version += 1;
  return true;
}

void PresentationDocument::ClearCueChecks()
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->checked_cues.empty()) {
    return;
  }
  impl_->checked_cues.clear();
  impl_->state_version += 1;
}

bool PresentationDocument::ExportCueList(std::string &out_path, std::string &out_error) const
{
  std::vector<CachedSlide> slides;
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
    current = impl_->current_index;
  }

  fs::path output = fs::path(Utf8ToWide(deck_path));
  output.replace_extension(L".pptbridge-cues.txt");

  std::ofstream file(output, std::ios::out | std::ios::trunc);
  if (!file) {
    out_error = "could not create cue list at " + WideToUtf8(output.wstring());
    return false;
  }

  file << "PPTBridge SK Cue List\n";
  file << "Deck: " << deck_name << "\n\n";
  for (std::size_t index = 0; index < slides.size(); ++index) {
    file << (checked_cues.find(index) != checked_cues.end() ? "[x] " : "[ ] ");
    if (index == current) {
      file << "> ";
    } else if (index == current + 1) {
      file << "next ";
    } else {
      file << "  ";
    }
    file << (index + 1) << ". " << CueTitleForSlide(slides, index) << "\n";
    const std::string notes = TrimWhitespaceCopy(slides[index].meta.notes);
    if (!notes.empty()) {
      file << "   Notes: " << notes << "\n";
    }
  }

  out_path = WideToUtf8(output.wstring());
  out_error.clear();
  return true;
}

bool PresentationDocument::RenderSlideBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride) const
{
  if (width == 0 || height == 0 || width > 7680 || height > 4320) {
    out_pixels.clear();
    out_stride = 0;
    return false;
  }

  std::lock_guard<std::mutex> render_lock(impl_->render_mutex);
  GlobalGdiPlus();

  Bitmap canvas(width, height, PixelFormat32bppARGB);
  Graphics graphics(&canvas);
  graphics.SetCompositingQuality(CompositingQualityHighQuality);
  graphics.SetInterpolationMode(InterpolationModeHighQualityBicubic);
  graphics.SetSmoothingMode(SmoothingModeHighQuality);

  std::wstring image_path;
  std::wstring message_title;
  std::wstring message_subtitle;
  bool black = false;

  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->black_screen) {
      black = true;
    } else if (impl_->loading) {
      message_title = L"PPTBridge SK";
      message_subtitle = L"Loading Windows PowerPoint deck...";
    } else if (!impl_->loaded) {
      message_title = L"PPTBridge SK";
      message_subtitle = impl_->last_error.empty()
        ? L"Select a PowerPoint file to begin."
        : Utf8ToWide(impl_->last_error);
    } else if (impl_->slides.empty()) {
      message_title = L"PPTBridge SK";
      message_subtitle = L"No exported slides were found for this PowerPoint file.";
    } else {
      image_path = impl_->slides[std::min(impl_->current_index, impl_->slides.size() - 1)].image_path;
    }
  }

  if (black) {
    SolidBrush fill(Color(255, 0, 0, 0));
    graphics.FillRectangle(&fill, 0, 0, width, height);
    return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
  }

  if (!message_subtitle.empty()) {
    DrawCenteredMessage(graphics, width, height, message_title, message_subtitle);
    return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
  }

  SolidBrush background(Color(255, 9, 12, 17));
  graphics.FillRectangle(&background, 0, 0, width, height);

  if (!DrawImageFile(graphics, image_path, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)))) {
    DrawCenteredMessage(graphics, width, height, L"PPTBridge SK", L"Could not render the exported slide image.");
  }

  return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
}

bool PresentationDocument::RenderPresenterBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride,
  const PresenterRenderOptions &options) const
{
  if (width == 0 || height == 0 || width > 7680 || height > 4320) {
    out_pixels.clear();
    out_stride = 0;
    return false;
  }

  std::lock_guard<std::mutex> render_lock(impl_->render_mutex);
  GlobalGdiPlus();

  Bitmap canvas(width, height, PixelFormat32bppARGB);
  Graphics graphics(&canvas);
  graphics.SetCompositingQuality(CompositingQualityHighQuality);
  graphics.SetInterpolationMode(InterpolationModeHighQualityBicubic);
  graphics.SetSmoothingMode(SmoothingModeHighQuality);

  size_t current_index = 0;
  size_t slide_count = 0;
  uint64_t seconds = 0;
  std::wstring current_image;
  std::wstring next_image;
  std::wstring notes;
  std::wstring title;
  std::wstring deck_name;
  std::wstring mode_label;
  std::wstring status_label;
  std::wstring footer_hint;
  std::wstring last_issue;
  bool current_has_media = false;
  std::vector<CachedSlide> slide_snapshot;
  std::set<std::size_t> checked_cues;

  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->loading) {
      DrawCenteredMessage(graphics, width, height, L"PPTBridge SK", L"Loading presenter view for Windows...");
      return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
    }

    if (!impl_->loaded || impl_->slides.empty()) {
      DrawCenteredMessage(
        graphics,
        width,
        height,
        L"PPTBridge SK",
        impl_->last_error.empty() ? L"No presenter assets are ready yet." : Utf8ToWide(impl_->last_error));
      return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
    }

    current_index = std::min(impl_->current_index, impl_->slides.size() - 1);
    slide_count = impl_->slides.size();
    slide_snapshot = impl_->slides;
    checked_cues = impl_->checked_cues;
    deck_name = Utf8ToWide(impl_->name);
    current_image = impl_->slides[current_index].image_path;
    notes = Utf8ToWide(impl_->slides[current_index].meta.notes);
    title = Utf8ToWide(impl_->slides[current_index].meta.title);
    current_has_media =
      current_index < impl_->media_by_slide.size() && !impl_->media_by_slide[current_index].empty();
    if (current_index + 1 < impl_->slides.size()) {
      next_image = impl_->slides[current_index + 1].image_path;
    }
    mode_label = impl_->live_enabled ? L"TRUE LIVE" : L"LEGACY";
    status_label = impl_->live_enabled
      ? (impl_->live_ready ? L"PowerPoint slideshow attached" : L"Preparing PowerPoint live session")
      : (current_has_media ? L"Legacy media-ready slide" : L"Legacy cached-render mode");
    footer_hint = current_has_media
      ? L"Media on this slide can be armed before advancing."
      : L"Use OBS hotkeys or clicker buttons to move through the deck.";
    if (!impl_->last_error.empty()) {
      last_issue = Utf8ToWide(impl_->last_error);
    }
    if (impl_->timer_started_at != std::chrono::steady_clock::time_point::min()) {
      seconds = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - impl_->timer_started_at).count());
    }
  }

  SolidBrush background(ColorFromRgb(options.background_color));
  SolidBrush panel(Color(255, 19, 23, 31));
  SolidBrush accent(Color(255, 84, 226, 170));
  SolidBrush title_brush(Color(255, 245, 247, 250));
  SolidBrush body_brush(Color(255, 195, 200, 214));
  SolidBrush muted_brush(Color(255, 141, 147, 165));
  SolidBrush badge_fill(Color(255, 28, 34, 46));
  SolidBrush success_fill(Color(255, 53, 86, 70));
  SolidBrush warning_fill(Color(255, 89, 64, 34));
  SolidBrush footer_fill(Color(255, 14, 18, 25));
  Pen border(Color(255, 42, 48, 64), 2.0f);

  const bool confidence_layout = options.layout == PresenterLayoutPreset::ConfidenceMonitor;
  const bool compact_layout = options.layout == PresenterLayoutPreset::Compact;
  const float top_bar_height = confidence_layout ? 0.0f : (compact_layout ? 44.0f : 56.0f);
  const float margin = compact_layout ? 10.0f : 18.0f;
  const float gap = compact_layout ? 10.0f : 16.0f;
  const float footer_height = compact_layout ? 42.0f : 54.0f;
  const float content_y = top_bar_height + margin;
  const float content_bottom = static_cast<float>(height) - footer_height - margin;
  const float content_height = std::max(1.0f, content_bottom - content_y);
  const float content_width = std::max(120.0f, static_cast<float>(width) - (margin * 2.0f));

  float right_ratio = 0.28f;
  float notes_base_ratio = 0.62f;
  if (options.layout == PresenterLayoutPreset::LargePreview) {
    right_ratio = 0.22f;
    notes_base_ratio = 0.56f;
  } else if (options.layout == PresenterLayoutPreset::LargeNotes) {
    right_ratio = 0.36f;
    notes_base_ratio = 0.76f;
  } else if (compact_layout) {
    right_ratio = 0.24f;
    notes_base_ratio = 0.58f;
  }

  RectF current_rect;
  RectF right_rect;
  RectF next_rect;
  RectF notes_rect;
  if (confidence_layout) {
    const float strip_ratio = ClampFloat(static_cast<float>(options.notes_area_percent) / 100.0f, 0.60f, 1.80f);
    float preview_height = 0.0f;
    float strip_height = 0.0f;
    SplitConfidenceHeights(content_height, gap, strip_ratio, preview_height, strip_height);
    current_rect = RectF(
      margin,
      content_y,
      content_width,
      preview_height);
    right_rect = RectF(margin, current_rect.Y + current_rect.Height + gap, content_width, strip_height);
    const float next_width = ClampFloat(right_rect.Width * 0.28f, 120.0f, right_rect.Width * 0.42f);
    next_rect = RectF(right_rect.X, right_rect.Y, next_width, right_rect.Height);
    notes_rect = RectF(
      next_rect.X + next_rect.Width + gap,
      right_rect.Y,
      std::max(80.0f, right_rect.Width - next_rect.Width - gap),
      right_rect.Height);
  } else {
    const float minimum_right = compact_layout ? 240.0f : 300.0f;
    const float maximum_right = std::max(180.0f, content_width - 220.0f - gap);
    const float right_panel_scale =
      ClampFloat(static_cast<float>(options.side_panel_width_percent) / 100.0f, 0.50f, 2.20f);
    const float right_width = ClampFloat(static_cast<float>(width) * right_ratio * right_panel_scale, minimum_right, maximum_right);
    current_rect = RectF(margin, content_y, content_width - right_width - gap, content_height);
    right_rect = RectF(current_rect.X + current_rect.Width + gap, content_y, right_width, content_height);

    const float notes_multiplier = ClampFloat(static_cast<float>(options.notes_area_percent) / 100.0f, 0.60f, 1.80f);
    const float notes_ratio = ClampFloat(notes_base_ratio * notes_multiplier, 0.38f, 0.86f);
    float next_height = 0.0f;
    float notes_height = 0.0f;
    SplitVerticalPanelHeights(right_rect.Height, gap, notes_ratio, next_height, notes_height);
    next_rect = RectF(right_rect.X, right_rect.Y, right_rect.Width, next_height);
    notes_rect = RectF(right_rect.X, right_rect.Y + next_height + gap, right_rect.Width, notes_height);
  }

  RectF cue_rect;
  if (options.show_cue_list && notes_rect.Height >= 150.0f) {
    const float cue_height = ClampFloat(notes_rect.Height * 0.28f, 92.0f, 172.0f);
    if (notes_rect.Height - cue_height - gap >= 72.0f) {
      cue_rect = RectF(notes_rect.X, notes_rect.Y + notes_rect.Height - cue_height, notes_rect.Width, cue_height);
      notes_rect.Height = std::max(1.0f, notes_rect.Height - cue_height - gap);
    }
  }

  graphics.FillRectangle(&background, 0, 0, width, height);
  DrawPresenterBackgroundImage(graphics, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)), options);
  graphics.FillRectangle(&accent, 0.0f, 0.0f, static_cast<REAL>(width), 6.0f);
  graphics.FillRectangle(&footer_fill, 0.0f, height - 42.0f, static_cast<REAL>(width), 42.0f);
  if (!confidence_layout) {
    graphics.FillRectangle(&panel, right_rect.X - (gap * 0.5f), 0.0f, static_cast<REAL>(width) - right_rect.X + (gap * 0.5f), static_cast<REAL>(height));
  }

  graphics.DrawRectangle(&border, current_rect.X, current_rect.Y, current_rect.Width, current_rect.Height);
  graphics.DrawRectangle(&border, next_rect.X, next_rect.Y, next_rect.Width, next_rect.Height);
  graphics.DrawRectangle(&border, notes_rect.X, notes_rect.Y, notes_rect.Width, notes_rect.Height);

  DrawImagePreview(graphics, current_image, current_rect, options);
  if (!next_image.empty()) {
    const RectF next_preview_rect(
      next_rect.X + 10.0f,
      next_rect.Y + 34.0f,
      std::max(1.0f, next_rect.Width - 20.0f),
      std::max(1.0f, next_rect.Height - 44.0f));
    DrawImagePreview(graphics, next_image, next_preview_rect, options);
  }

  Font header_font(L"Segoe UI Semibold", compact_layout ? 22.0f : 28.0f, FontStyleBold, UnitPixel);
  Font label_font(L"Segoe UI Semibold", 18.0f, FontStyleBold, UnitPixel);
  const float notes_zoom = ClampFloat(static_cast<float>(options.notes_zoom_percent) / 100.0f, 0.50f, 2.00f);
  Font notes_font(
    L"Segoe UI",
    ClampFloat(static_cast<float>(options.notes_font_size) * notes_zoom, 8.0f, 64.0f),
    FontStyleRegular,
    UnitPixel);
  Font small_font(L"Segoe UI", 16.0f, FontStyleRegular, UnitPixel);
  Font tiny_font(L"Segoe UI", 14.0f, FontStyleRegular, UnitPixel);

  const float label_x = confidence_layout ? margin : right_rect.X;
  if (!confidence_layout) {
    graphics.DrawString(L"PPTBridge SK Presenter", -1, &header_font, PointF(label_x, compact_layout ? 20.0f : 44.0f), &title_brush);
    if (!deck_name.empty() && !compact_layout) {
      graphics.DrawString(deck_name.c_str(), -1, &small_font, PointF(label_x, 72.0f), &muted_brush);
    }
  }

  const auto timer = FormatDuration(seconds);
  std::wstringstream slide_counter;
  slide_counter << L"Slide " << (current_index + 1) << L" / " << slide_count;
  graphics.DrawString(slide_counter.str().c_str(), -1, &label_font, PointF(label_x, height - 34.0f), &title_brush);
  graphics.DrawString(timer.c_str(), -1, &small_font, PointF(width - 120.0f, height - 32.0f), &accent);

  if (!confidence_layout) {
    const RectF mode_badge(label_x, compact_layout ? 50.0f : 124.0f, 120.0f, 30.0f);
    SolidBrush &mode_brush = (mode_label == L"TRUE LIVE") ? success_fill : badge_fill;
    graphics.FillRectangle(&mode_brush, mode_badge);
    graphics.DrawString(mode_label.c_str(), -1, &tiny_font, RectF(mode_badge.X + 10.0f, mode_badge.Y + 6.0f, mode_badge.Width - 20.0f, 20.0f), nullptr, &title_brush);

    const RectF status_badge(label_x, mode_badge.Y + 38.0f, right_rect.Width, 44.0f);
    SolidBrush &status_brush = (!last_issue.empty()) ? warning_fill : badge_fill;
    graphics.FillRectangle(&status_brush, status_badge);
    graphics.DrawString(status_label.c_str(), -1, &tiny_font, RectF(status_badge.X + 10.0f, status_badge.Y + 8.0f, status_badge.Width - 20.0f, 28.0f), nullptr, &title_brush);
  }

  graphics.DrawString(L"Next", -1, &label_font, PointF(next_rect.X + 10.0f, next_rect.Y + 8.0f), &muted_brush);
  graphics.DrawString(L"Notes", -1, &label_font, PointF(notes_rect.X + 10.0f, notes_rect.Y + 8.0f), &muted_brush);

  std::wstring header_title = title.empty() ? L"Current slide" : title;
  const float current_title_y = current_rect.Y >= 32.0f ? current_rect.Y - 28.0f : current_rect.Y + 8.0f;
  graphics.DrawString(header_title.c_str(), -1, &small_font, PointF(current_rect.X + 8.0f, current_title_y), &muted_brush);

  if (notes.empty()) {
    notes = L"No presenter notes on this slide.";
  }

  StringFormat notes_format;
  notes_format.SetTrimming(StringTrimmingEllipsisWord);
  notes_format.SetFormatFlags(StringFormatFlagsLineLimit);
  const float notes_text_height = std::max(1.0f, notes_rect.Height - 48.0f);
  const float notes_offset_y =
    (ClampFloat(static_cast<float>(options.notes_position_y), -100.0f, 100.0f) / 100.0f) *
    notes_text_height *
    0.35f;
  graphics.DrawString(
    notes.c_str(),
    -1,
    &notes_font,
    RectF(
      notes_rect.X + 12.0f,
      notes_rect.Y + 36.0f + notes_offset_y,
      std::max(1.0f, notes_rect.Width - 24.0f),
      notes_text_height),
    &notes_format,
    &body_brush);

  if (cue_rect.Width > 0.0f && cue_rect.Height > 0.0f) {
    DrawCueList(graphics, slide_snapshot, checked_cues, current_index, slide_count, cue_rect);
  }

  if (!last_issue.empty() && !confidence_layout) {
    RectF issue_rect(label_x, height - 108.0f, right_rect.Width, 52.0f);
    graphics.FillRectangle(&warning_fill, issue_rect);
    graphics.DrawString(last_issue.c_str(), -1, &tiny_font, RectF(issue_rect.X + 10.0f, issue_rect.Y + 8.0f, issue_rect.Width - 20.0f, issue_rect.Height - 16.0f), &notes_format, &title_brush);
  }

  graphics.DrawString(footer_hint.c_str(), -1, &tiny_font, RectF(24.0f, height - 30.0f, width - 48.0f, 20.0f), nullptr, &muted_brush);

  return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
}

void PresentationDocument::StartLoadIfNeeded(bool force_reload)
{
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (force_reload) {
      impl_->force_reload = true;
      impl_->load_requested = true;
    }
    if (impl_->loading) {
      return;
    }
    if (!impl_->load_requested) {
      return;
    }

    impl_->loading = true;
    impl_->load_requested = false;
    impl_->active_force_reload = impl_->force_reload;
    impl_->force_reload = false;
    impl_->last_error.clear();
    impl_->state_version += 1;
  }

  auto self = shared_from_this();
  std::thread([self]() {
    self->LoadOnWorker();
  }).detach();
}

void PresentationDocument::LoadOnWorker()
{
  const auto load_started = std::chrono::steady_clock::now();
  const auto elapsed_ms = [](const std::chrono::steady_clock::time_point &started) {
    return static_cast<long long>(std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - started).count());
  };
  const auto fail_load = [this](std::string message) {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->slides.clear();
    impl_->media_by_slide.clear();
    impl_->loaded = false;
    impl_->loading = false;
    impl_->load_requested = false;
    impl_->active_force_reload = false;
    if (impl_->live_start_requested) {
      impl_->live_start_requested = false;
      impl_->live_request_generation += 1;
    }
    impl_->live_ready = false;
    impl_->live_window_title.clear();
    impl_->current_index = 0;
    impl_->current_media_triggered = false;
    impl_->last_error = std::move(message);
    impl_->state_version += 1;
  };

  const fs::path source_path(Utf8ToWide(impl_->path));
  std::error_code input_error;
  if (!fs::exists(source_path, input_error) || !fs::is_regular_file(source_path, input_error)) {
    fail_load("The selected presentation file could not be found or is not a regular file.");
    return;
  }

  const auto input_size = fs::file_size(source_path, input_error);
  if (input_error || input_size == 0) {
    fail_load("The selected presentation file is empty or cannot be read.");
    return;
  }

  if (IsPdfExtension(impl_->path)) {
    fail_load(
      "PDF input is not supported on Windows. Choose a PowerPoint file such as .pptx; PDF support remains a macOS-only feature for now.");
    return;
  }

  if (!IsSupportedPowerPointExtension(impl_->path)) {
    fail_load(
      "Unsupported presentation type. Windows accepts .ppt, .pptx, .pptm, .ppsx, .potx, and .potm PowerPoint files.");
    return;
  }

  const std::string current_stamp = CurrentFileStamp(source_path);
  const fs::path metadata_path = impl_->metadata_path;
  ParsedDeckData deck_data;
  std::string load_error;

  bool force_reload = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    force_reload = impl_->active_force_reload;
    impl_->file_stamp = current_stamp;
  }

  bool reused_cache = false;
  bool skip_embedded_media = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    skip_embedded_media = impl_->live_enabled;
  }
  if (!force_reload && LoadCachedSlides(
        metadata_path,
        current_stamp,
        !skip_embedded_media,
        deck_data)) {
    reused_cache = true;
    blog(LOG_INFO, "[PPTBridge SK] Reused cached Windows slide export for '%s'", impl_->path.c_str());
  } else {
    std::string output;
    int exit_code = -1;
    {
      std::lock_guard<std::mutex> script_lock(impl_->script_mutex);
        RunPowerShellMode(
          L"export",
          Utf8ToWide(impl_->path),
          impl_->cache_root.wstring(),
          0,
          output,
          exit_code,
          skip_embedded_media);
    }

    if (exit_code != 0 || !ParseExportOutput(output, deck_data, load_error)) {
      if (load_error.empty()) {
        load_error = output.empty() ? "PowerPoint export failed on Windows." : output;
      }
    } else {
      SaveCachedSlides(
        metadata_path,
        current_stamp,
        deck_data.slides,
        deck_data.media_by_slide,
        deck_data.slide_aspect_ratio,
        deck_data.media_scan_complete);
    }
  }

  LiveSnapshot live_snapshot;
  std::string live_error;
  bool live_enabled = false;
  bool should_start_live = false;
  uint64_t live_request_generation = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->slides = std::move(deck_data.slides);
    impl_->media_by_slide = std::move(deck_data.media_by_slide);
    if (deck_data.slide_aspect_ratio >= 0.2 && deck_data.slide_aspect_ratio <= 10.0) {
      impl_->slide_aspect_ratio = deck_data.slide_aspect_ratio;
    }
    if (impl_->media_by_slide.size() < impl_->slides.size()) {
      impl_->media_by_slide.resize(impl_->slides.size());
    }
    impl_->loaded = !impl_->slides.empty();
    if (!impl_->live_ready) {
      impl_->current_index = 0;
    }
    impl_->current_media_triggered = false;
    impl_->last_error = load_error;
    live_enabled = impl_->live_enabled;
    should_start_live = impl_->live_enabled && (impl_->live_auto_start || impl_->live_start_requested);
    live_request_generation = impl_->live_request_generation;
    if (should_start_live && impl_->load_requested && !impl_->force_reload) {
      // A Start pressed while export was running is consumed by this worker.
      impl_->load_requested = false;
    }
    impl_->state_version += 1;
  }

  if (should_start_live) {
    std::string output;
    int exit_code = -1;
    bool command_is_current = false;
    const auto live_start_started = std::chrono::steady_clock::now();
    {
      std::lock_guard<std::mutex> script_lock(impl_->script_mutex);
      {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        command_is_current =
          impl_->live_enabled &&
          impl_->live_start_requested &&
          impl_->live_request_generation == live_request_generation;
      }
      if (command_is_current) {
        RunPowerShellMode(L"live-start", Utf8ToWide(impl_->path), impl_->cache_root.wstring(), 0, output, exit_code);
      }

      const bool started =
        command_is_current &&
        exit_code == 0 &&
        ParseLiveSnapshot(output, live_snapshot, live_error) &&
        live_snapshot.running;
      bool keep_started_session = false;
      bool stop_stale_session = false;
      {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        keep_started_session =
          started &&
          impl_->live_enabled &&
          impl_->live_start_requested &&
          impl_->live_request_generation == live_request_generation;
        if (keep_started_session) {
          impl_->live_ready = true;
          impl_->loaded = true;
          impl_->live_window_title = live_snapshot.window_title;
          if (live_snapshot.slide_aspect_ratio >= 0.2 && live_snapshot.slide_aspect_ratio <= 10.0) {
            impl_->slide_aspect_ratio = live_snapshot.slide_aspect_ratio;
          }
          if (impl_->slides.empty() && live_snapshot.slide_count > 0) {
            impl_->slides.resize(live_snapshot.slide_count);
            impl_->media_by_slide.resize(live_snapshot.slide_count);
            for (size_t index = 0; index < impl_->slides.size(); ++index) {
              impl_->slides[index].meta.title = "Slide " + std::to_string(index + 1);
            }
          }
          if (!impl_->slides.empty() && live_snapshot.current_slide > 0) {
            impl_->current_index = std::min(live_snapshot.current_slide - 1, impl_->slides.size() - 1);
          }
          impl_->current_media_triggered = false;
          impl_->timer_started_at = std::chrono::steady_clock::now();
          impl_->live_last_sync = std::chrono::steady_clock::time_point::min();
          impl_->last_error = load_error.empty()
            ? std::string()
            : "Live slideshow is running, but fallback export failed. Presenter notes and static fallback may be limited.";
          impl_->state_version += 1;
        } else if (command_is_current &&
                   impl_->live_request_generation == live_request_generation &&
                   impl_->live_start_requested) {
          impl_->live_ready = false;
          impl_->live_window_title.clear();
          impl_->last_error = !live_error.empty()
            ? live_error
            : (output.empty() ? "PowerPoint live slideshow did not start." : output);
          impl_->state_version += 1;
        }
        stop_stale_session = started && !keep_started_session && !impl_->live_start_requested;
      }

      if (stop_stale_session) {
        std::string stop_output;
        int stop_exit_code = -1;
        RunPowerShellMode(
          L"live-stop",
          Utf8ToWide(impl_->path),
          impl_->cache_root.wstring(),
          0,
          stop_output,
          stop_exit_code);
      }

      if (keep_started_session) {
        blog(
          LOG_INFO,
          "[PPTBridge SK] Windows PowerPoint live mode started for '%s' in %lld ms",
          impl_->path.c_str(),
          elapsed_ms(live_start_started));
      } else if (started) {
        blog(LOG_INFO, "[PPTBridge SK] Discarded stale Windows live-start result for '%s'", impl_->path.c_str());
      } else if (command_is_current) {
        blog(
          LOG_WARNING,
          "[PPTBridge SK] Windows live mode failed for '%s' after %lld ms: %s",
          impl_->path.c_str(),
          elapsed_ms(live_start_started),
          (!live_error.empty() ? live_error : output).c_str());
      }
    }
  }

  bool restart_for_queued_request = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->loading = false;
    impl_->active_force_reload = false;
    restart_for_queued_request = impl_->load_requested;
    impl_->state_version += 1;
  }

  blog(
    LOG_INFO,
    "[PPTBridge SK] Prepared Windows deck '%s' in %lld ms (%s)",
    impl_->path.c_str(),
    elapsed_ms(load_started),
    reused_cache ? "cached slide export" : "fresh PowerPoint export");

  if (!load_error.empty() && !live_enabled) {
    blog(LOG_WARNING, "[PPTBridge SK] Windows export failed for '%s': %s", impl_->path.c_str(), load_error.c_str());
  } else if (!load_error.empty() && live_error.empty() && live_snapshot.running) {
    blog(
      LOG_WARNING,
      "[PPTBridge SK] Windows export fallback failed for '%s', but live slideshow started successfully: %s",
      impl_->path.c_str(),
      load_error.c_str());
  } else if (!load_error.empty()) {
    blog(LOG_WARNING, "[PPTBridge SK] Windows export failed for '%s': %s", impl_->path.c_str(), load_error.c_str());
  }

  if (restart_for_queued_request) {
    blog(LOG_INFO, "[PPTBridge SK] Continuing queued Windows load/start request for '%s'", impl_->path.c_str());
    StartLoadIfNeeded(false);
  }
}

}  // namespace pptbridge

#endif  // _WIN32
