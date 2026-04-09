#include "presentation_document.hpp"

#ifdef _WIN32

#include <obs-module.h>

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <gdiplus.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;
using namespace Gdiplus;

namespace pptbridge {

namespace {

constexpr const wchar_t *kPowerShellExe = L"powershell.exe";
constexpr uint32_t kExportWidth = 1920;
constexpr uint32_t kExportHeight = 1080;

struct CachedSlide {
  std::wstring image_path;
  SlideMetadata meta;
};

struct ParsedDeckData {
  std::vector<CachedSlide> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
};

struct LiveSnapshot {
  bool running = false;
  size_t current_slide = 0;
  size_t slide_count = 0;
  std::string presentation_title;
  std::string window_title;
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

bool RunProcessCapture(const std::vector<std::wstring> &args, std::string &out_output, int &out_exit_code)
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
  DWORD bytes_read = 0;
  while (ReadFile(read_pipe, buffer, sizeof(buffer), &bytes_read, nullptr) && bytes_read > 0) {
    out_output.append(buffer, buffer + bytes_read);
  }

  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 0;
  GetExitCodeProcess(process.hProcess, &exit_code);
  out_exit_code = static_cast<int>(exit_code);

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  CloseHandle(read_pipe);
  return true;
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
  const std::vector<std::vector<EmbeddedMedia>> &media_by_slide)
{
  std::ostringstream output;
  output << "STAMP|" << stamp << "\n";
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

bool LoadCachedSlides(const fs::path &metadata_path, const std::string &stamp, ParsedDeckData &out_deck)
{
  const auto contents = ReadUtf8File(metadata_path);
  if (contents.empty()) {
    return false;
  }

  std::vector<CachedSlide> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  for (const auto &line : SplitLines(contents)) {
    if (line.rfind("STAMP|", 0) == 0) {
      if (line.substr(6) != stamp) {
        return false;
      }
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

  if (slides.empty()) {
    return false;
  }

  if (media_by_slide.size() < slides.size()) {
    media_by_slide.resize(slides.size());
  }

  out_deck.slides = std::move(slides);
  out_deck.media_by_slide = std::move(media_by_slide);
  return true;
}

std::string BuildWindowsPowerShellScript()
{
  return R"POWERSHELL(
param(
  [Parameter(Mandatory = $true)][string]$Mode,
  [string]$PptxPath,
  [string]$CacheDir,
  [int]$Width = 1920,
  [int]$Height = 1080,
  [int]$TargetSlide = 1
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Escape-PPTBridgeValue([string]$Value) {
  if ($null -eq $Value) { return "" }
  $Value = $Value.Replace('\', '\\')
  $Value = $Value.Replace('|', '\p')
  $Value = $Value.Replace("`r", '\r')
  $Value = $Value.Replace("`n", '\n')
  return $Value
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

function Get-PPTBridgeMediaForSlide($Archive, [string]$SlideEntry, [string]$CacheDir, [double]$SlideWidth, [double]$SlideHeight, $ExtractedCache) {
  $results = New-Object System.Collections.Generic.List[object]
  $signatures = New-Object 'System.Collections.Generic.HashSet[string]'
  $slideXml = Get-PPTBridgeZipEntryText $Archive $SlideEntry
  if ([string]::IsNullOrWhiteSpace($slideXml)) { return @($results) }

  $relsEntry = ([System.IO.Path]::GetDirectoryName($SlideEntry).Replace('\', '/')) + "/_rels/" + [System.IO.Path]::GetFileName($SlideEntry) + ".rels"
  $relationships = Get-PPTBridgeZipRelationships $Archive $relsEntry
  if ($relationships.Count -eq 0) { return @($results) }

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

  return @($results)
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

function Find-PPTBridgePresentation($App, [string]$Path) {
  if ($null -eq $App -or [string]::IsNullOrWhiteSpace($Path)) { return $null }
  $targetName = [System.IO.Path]::GetFileName($Path)
  foreach ($presentation in @($App.Presentations)) {
    try {
      if ($presentation.FullName -eq $Path -or $presentation.Name -eq $targetName) {
        return $presentation
      }
    } catch {}
  }
  return $null
}

function Open-PPTBridgePresentation($App, [string]$Path, [bool]$WithWindow) {
  $presentation = Find-PPTBridgePresentation $App $Path
  if ($presentation) { return $presentation }
  return $App.Presentations.Open($Path, $false, $false, $WithWindow)
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
    return
  }

  $slideCount = 0
  try { $slideCount = [int]$Presentation.Slides.Count } catch {}
  $current = 0
  try { $current = [int]$Window.View.CurrentShowPosition } catch {}
  $title = ""
  try { $title = [string]$Presentation.Name } catch {}
  $windowTitle = "PowerPoint Slide Show - [" + [System.IO.Path]::GetFileNameWithoutExtension($title) + "]"

  Write-Output "RUNNING|1"
  Write-Output ("SLIDE|{0}" -f $current)
  Write-Output ("COUNT|{0}" -f $slideCount)
  Write-Output ("TITLE|{0}" -f (Escape-PPTBridgeValue $title))
  Write-Output ("WINDOW|{0}" -f (Escape-PPTBridgeValue $windowTitle))
}

switch ($Mode) {
  "export" {
    if ([string]::IsNullOrWhiteSpace($PptxPath) -or [string]::IsNullOrWhiteSpace($CacheDir)) {
      throw "Export mode expects PptxPath and CacheDir."
    }

    $slidesDir = Join-Path $CacheDir "slides"
    New-Item -ItemType Directory -Force -Path $slidesDir | Out-Null
    $archive = $null
    $app = $null
    $presentation = $null
    try {
      $archive = [System.IO.Compression.ZipFile]::OpenRead($PptxPath)
      $slideEntries = Get-PPTBridgeSlideEntries $archive
      $slideSize = Get-PPTBridgeSlideSize $archive
      $extractedMediaCache = @{}

      $app = New-Object -ComObject PowerPoint.Application
      $app.Visible = $true
      $presentation = Open-PPTBridgePresentation $app $PptxPath $false
      $presentation.Export($slidesDir, "PNG", $Width, $Height)

      Write-Output "OK"
      Write-Output ("COUNT|{0}" -f [int]$presentation.Slides.Count)

      foreach ($slide in @($presentation.Slides)) {
        $index = [int]$slide.SlideIndex
        $file = Join-Path $slidesDir ("Slide{0}.PNG" -f $index)
        if (-not (Test-Path -LiteralPath $file)) {
          $file = Join-Path $slidesDir ("Slide{0}.png" -f $index)
        }
        if (-not (Test-Path -LiteralPath $file)) {
          $fallback = @(Get-ChildItem -LiteralPath $slidesDir -Filter ("Slide{0}.*" -f $index))
          if ($fallback.Count -gt 0) {
            $file = $fallback[0].FullName
          }
        }

        $title = ""
        try { $title = [string]$slide.Name } catch {}
        $notes = Get-PPTBridgeNotes $slide
        Write-Output ("SLIDE|{0}|{1}|{2}|{3}" -f
          $index,
          (Escape-PPTBridgeValue $file),
          (Escape-PPTBridgeValue $title),
          (Escape-PPTBridgeValue $notes))

        if ($index -le $slideEntries.Count) {
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
      if ($null -ne $presentation) {
        try { $presentation.Close() } catch {}
      }
      if ($null -ne $app) {
        try { $app.Quit() } catch {}
      }
    }
  }

  "live-start" {
    if ([string]::IsNullOrWhiteSpace($PptxPath)) {
      throw "live-start expects PptxPath."
    }

    $app = Get-PPTBridgeApp $true
    $app.Visible = $true
    $presentation = Open-PPTBridgePresentation $app $PptxPath $true
    $window = Get-PPTBridgeWindow $app $presentation
    if ($null -eq $window) {
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

  "next" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) { $window.View.Next() }
    Emit-PPTBridgeSnapshot $window $presentation
  }

  "previous" {
    $app = Get-PPTBridgeApp $false
    $presentation = Find-PPTBridgePresentation $app $PptxPath
    $window = Get-PPTBridgeWindow $app $presentation
    if ($window) { $window.View.Previous() }
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
  int &out_exit_code)
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

  return RunProcessCapture(args, out_stdout, out_exit_code);
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

  if (!ok || out_deck.slides.empty()) {
    out_error = output.empty() ? "PowerPoint export produced no usable slide output." : output;
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
  std::string path;
  std::string name;
  fs::path cache_root;
  fs::path metadata_path;
  std::string file_stamp;
  std::vector<CachedSlide> slides;
  std::vector<std::vector<EmbeddedMedia>> media_by_slide;
  size_t current_index = 0;
  bool current_media_triggered = false;
  bool loaded = false;
  bool loading = false;
  bool force_reload = false;
  bool black_screen = false;
  bool live_enabled = true;
  bool live_ready = false;
  bool presenter_assets_wanted = false;
  std::string live_window_title;
  std::string last_error;
  uint64_t state_version = 1;
  std::chrono::steady_clock::time_point timer_started_at = std::chrono::steady_clock::time_point::min();
  std::atomic_bool live_sync_inflight = false;
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
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->live_enabled = enabled;
    if (!enabled) {
      impl_->live_ready = false;
      impl_->live_window_title.clear();
      impl_->current_media_triggered = false;
      impl_->state_version += 1;
    }
  }

  if (enabled) {
    SyncLiveStateAsync();
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
  return impl_->live_ready;
}

std::string PresentationDocument::LiveWindowTitle() const
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->live_window_title;
}

void PresentationDocument::SyncLiveStateAsync()
{
  bool should_sync = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    should_sync = impl_->live_enabled && impl_->loaded;
  }

  if (!should_sync) {
    return;
  }

  bool expected = false;
  if (!impl_->live_sync_inflight.compare_exchange_strong(expected, true)) {
    return;
  }

  auto self = shared_from_this();
  std::thread([self]() {
    LiveSnapshot snapshot;
    std::string error;
    std::string output;
    int exit_code = -1;

    {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      RunPowerShellMode(
        L"live-state",
        Utf8ToWide(self->impl_->path),
        self->impl_->cache_root.wstring(),
        0,
        output,
        exit_code);
    }

    if (exit_code == 0 && ParseLiveSnapshot(output, snapshot, error)) {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      self->impl_->live_ready = snapshot.running;
      if (snapshot.slide_count > 0) {
        self->impl_->current_index = std::min(
          snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
          snapshot.slide_count - 1);
      }
      if (!snapshot.window_title.empty()) {
        self->impl_->live_window_title = snapshot.window_title;
      }
      if (snapshot.running && self->impl_->timer_started_at == std::chrono::steady_clock::time_point::min()) {
        self->impl_->timer_started_at = std::chrono::steady_clock::now();
      }
      if (snapshot.running) {
        self->impl_->current_media_triggered = false;
      }
      self->impl_->state_version += 1;
      self->impl_->last_error.clear();
    } else if (!error.empty()) {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      self->impl_->last_error = error;
    }

    self->impl_->live_sync_inflight.store(false);
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

void PresentationDocument::Next()
{
  bool use_live = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    use_live = impl_->live_enabled && impl_->live_ready;
    if (!use_live) {
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

  auto self = shared_from_this();
  std::thread([self]() {
    std::string output;
    int exit_code = -1;
    std::string error;
    LiveSnapshot snapshot;
    {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      RunPowerShellMode(L"next", Utf8ToWide(self->impl_->path), self->impl_->cache_root.wstring(), 0, output, exit_code);
    }

    if (exit_code == 0 && ParseLiveSnapshot(output, snapshot, error)) {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      if (snapshot.running && snapshot.slide_count > 0) {
        self->impl_->current_index = std::min(snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
                                               snapshot.slide_count - 1);
        self->impl_->live_ready = true;
        self->impl_->live_window_title = snapshot.window_title;
        self->impl_->last_error.clear();
        self->impl_->black_screen = false;
        self->impl_->current_media_triggered = false;
        if (self->impl_->timer_started_at == std::chrono::steady_clock::time_point::min()) {
          self->impl_->timer_started_at = std::chrono::steady_clock::now();
        }
        self->impl_->state_version += 1;
        return;
      }

      const bool has_media_on_current =
        self->impl_->current_index < self->impl_->media_by_slide.size() &&
        !self->impl_->media_by_slide[self->impl_->current_index].empty();
      if (has_media_on_current && !self->impl_->current_media_triggered) {
        self->impl_->current_media_triggered = true;
      } else if (self->impl_->current_index + 1 < self->impl_->slides.size()) {
        self->impl_->current_index += 1;
        self->impl_->current_media_triggered = false;
      }
      self->impl_->state_version += 1;
      self->impl_->black_screen = false;
    } else {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      const bool has_media_on_current =
        self->impl_->current_index < self->impl_->media_by_slide.size() &&
        !self->impl_->media_by_slide[self->impl_->current_index].empty();
      if (has_media_on_current && !self->impl_->current_media_triggered) {
        self->impl_->current_media_triggered = true;
      } else if (self->impl_->current_index + 1 < self->impl_->slides.size()) {
        self->impl_->current_index += 1;
        self->impl_->current_media_triggered = false;
      }
      self->impl_->last_error = error.empty() ? output : error;
      self->impl_->state_version += 1;
      self->impl_->black_screen = false;
    }
  }).detach();
}

void PresentationDocument::Previous()
{
  auto self = shared_from_this();
  std::thread([self]() {
    std::string output;
    int exit_code = -1;
    std::string error;
    LiveSnapshot snapshot;
    bool use_live = false;
    {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      use_live = self->impl_->live_enabled && self->impl_->live_ready;
    }

    if (use_live) {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      RunPowerShellMode(
        L"previous",
        Utf8ToWide(self->impl_->path),
        self->impl_->cache_root.wstring(),
        0,
        output,
        exit_code);
    }

    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    if (use_live && exit_code == 0 && ParseLiveSnapshot(output, snapshot, error) && snapshot.running && snapshot.slide_count > 0) {
      self->impl_->current_index = std::min(snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
                                            snapshot.slide_count - 1);
      self->impl_->live_ready = true;
      self->impl_->live_window_title = snapshot.window_title;
      self->impl_->last_error.clear();
      self->impl_->current_media_triggered = false;
    } else {
      if (self->impl_->current_media_triggered) {
        self->impl_->current_media_triggered = false;
      } else if (self->impl_->current_index > 0) {
        self->impl_->current_index -= 1;
      }
      if (!error.empty()) {
        self->impl_->last_error = error;
      }
    }
    self->impl_->black_screen = false;
    self->impl_->state_version += 1;
  }).detach();
}

void PresentationDocument::First()
{
  GoTo(0);
}

void PresentationDocument::Last()
{
  size_t target = 0;
  bool has_slides = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    has_slides = !impl_->slides.empty();
    if (has_slides) {
      target = impl_->slides.size() - 1;
    }
  }

  if (has_slides) {
    GoTo(target);
  }
}

void PresentationDocument::GoTo(std::size_t index)
{
  auto self = shared_from_this();
  std::thread([self, index]() {
    std::string output;
    int exit_code = -1;
    std::string error;
    LiveSnapshot snapshot;
    bool use_live = false;
    size_t slide_count = 0;
    {
      std::lock_guard<std::mutex> lock(self->impl_->mutex);
      use_live = self->impl_->live_enabled && self->impl_->live_ready;
      slide_count = self->impl_->slides.size();
    }

    const size_t clamped = slide_count == 0 ? 0 : std::min(index, slide_count - 1);
    if (use_live) {
      std::lock_guard<std::mutex> script_lock(self->impl_->script_mutex);
      RunPowerShellMode(
        L"goto",
        Utf8ToWide(self->impl_->path),
        self->impl_->cache_root.wstring(),
        static_cast<int>(clamped + 1),
        output,
        exit_code);
    }

    std::lock_guard<std::mutex> lock(self->impl_->mutex);
    if (use_live && exit_code == 0 && ParseLiveSnapshot(output, snapshot, error) && snapshot.running && snapshot.slide_count > 0) {
      self->impl_->current_index = std::min(snapshot.current_slide > 0 ? snapshot.current_slide - 1 : size_t{0},
                                            snapshot.slide_count - 1);
      self->impl_->live_ready = true;
      self->impl_->live_window_title = snapshot.window_title;
      self->impl_->last_error.clear();
      self->impl_->current_media_triggered = false;
    } else {
      self->impl_->current_index = clamped;
      self->impl_->current_media_triggered = false;
      if (!error.empty()) {
        self->impl_->last_error = error;
      }
    }
    self->impl_->black_screen = false;
    self->impl_->state_version += 1;
  }).detach();
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

bool PresentationDocument::RenderSlideBGRA(
  uint32_t width,
  uint32_t height,
  std::vector<uint8_t> &out_pixels,
  uint32_t &out_stride) const
{
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
      message_subtitle = L"Loading Windows PowerPoint deck…";
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
  uint32_t &out_stride) const
{
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

  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->loading) {
      DrawCenteredMessage(graphics, width, height, L"PPTBridge SK", L"Loading presenter view for Windows…");
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
    current_image = impl_->slides[current_index].image_path;
    notes = Utf8ToWide(impl_->slides[current_index].meta.notes);
    title = Utf8ToWide(impl_->slides[current_index].meta.title);
    if (current_index + 1 < impl_->slides.size()) {
      next_image = impl_->slides[current_index + 1].image_path;
    }
    if (impl_->timer_started_at != std::chrono::steady_clock::time_point::min()) {
      seconds = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - impl_->timer_started_at).count());
    }
  }

  SolidBrush background(Color(255, 9, 12, 17));
  SolidBrush panel(Color(255, 19, 23, 31));
  SolidBrush accent(Color(255, 84, 226, 170));
  SolidBrush title_brush(Color(255, 245, 247, 250));
  SolidBrush body_brush(Color(255, 195, 200, 214));
  SolidBrush muted_brush(Color(255, 141, 147, 165));
  Pen border(Color(255, 42, 48, 64), 2.0f);

  graphics.FillRectangle(&background, 0, 0, width, height);
  graphics.FillRectangle(&panel, width * 0.68f, 0.0f, width * 0.32f, static_cast<REAL>(height));
  graphics.FillRectangle(&accent, 0.0f, 0.0f, static_cast<REAL>(width), 6.0f);

  const RectF current_rect(40.0f, 48.0f, width * 0.62f, height - 96.0f);
  const RectF next_rect(width * 0.72f, 132.0f, width * 0.22f, height * 0.18f);
  const RectF notes_rect(width * 0.72f, 360.0f, width * 0.22f, height - 420.0f);

  graphics.DrawRectangle(&border, current_rect.X, current_rect.Y, current_rect.Width, current_rect.Height);
  graphics.DrawRectangle(&border, next_rect.X, next_rect.Y, next_rect.Width, next_rect.Height);
  graphics.DrawRectangle(&border, notes_rect.X, notes_rect.Y, notes_rect.Width, notes_rect.Height);

  DrawImageFile(graphics, current_image, current_rect);
  if (!next_image.empty()) {
    DrawImageFile(graphics, next_image, next_rect);
  }

  Font header_font(L"Segoe UI Semibold", 28.0f, FontStyleBold, UnitPixel);
  Font label_font(L"Segoe UI Semibold", 18.0f, FontStyleBold, UnitPixel);
  Font notes_font(L"Segoe UI", 20.0f, FontStyleRegular, UnitPixel);
  Font small_font(L"Segoe UI", 16.0f, FontStyleRegular, UnitPixel);

  graphics.DrawString(L"PPTBridge SK Presenter", -1, &header_font, PointF(width * 0.72f, 44.0f), &title_brush);

  const auto timer = FormatDuration(seconds);
  std::wstringstream slide_counter;
  slide_counter << L"Slide " << (current_index + 1) << L" / " << slide_count;
  graphics.DrawString(slide_counter.str().c_str(), -1, &label_font, PointF(width * 0.72f, 86.0f), &title_brush);
  graphics.DrawString(timer.c_str(), -1, &small_font, PointF(width * 0.92f, 88.0f), &accent);

  graphics.DrawString(L"Next", -1, &label_font, PointF(width * 0.72f, 106.0f), &muted_brush);
  graphics.DrawString(L"Notes", -1, &label_font, PointF(width * 0.72f, 332.0f), &muted_brush);

  std::wstring header_title = title.empty() ? L"Current slide" : title;
  graphics.DrawString(header_title.c_str(), -1, &small_font, PointF(48.0f, 14.0f), &muted_brush);

  if (notes.empty()) {
    notes = L"No presenter notes on this slide.";
  }

  StringFormat notes_format;
  notes_format.SetTrimming(StringTrimmingEllipsisWord);
  notes_format.SetFormatFlags(StringFormatFlagsLineLimit);
  graphics.DrawString(notes.c_str(), -1, &notes_font, notes_rect, &notes_format, &body_brush);

  return CopyBitmapToBGRA(canvas, out_pixels, out_stride);
}

void PresentationDocument::StartLoadIfNeeded(bool force_reload)
{
  bool should_start = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->loading) {
      if (force_reload) {
        impl_->force_reload = true;
      }
      return;
    }

    if (impl_->loaded && !force_reload) {
      return;
    }

    impl_->loading = true;
    impl_->force_reload = force_reload;
    impl_->last_error.clear();
    impl_->state_version += 1;
    should_start = true;
  }

  if (!should_start) {
    return;
  }

  auto self = shared_from_this();
  std::thread([self]() {
    self->LoadOnWorker();
  }).detach();
}

void PresentationDocument::LoadOnWorker()
{
  const fs::path source_path(Utf8ToWide(impl_->path));
  const std::string current_stamp = CurrentFileStamp(source_path);
  const fs::path metadata_path = impl_->metadata_path;
  ParsedDeckData deck_data;
  std::string load_error;

  bool force_reload = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    force_reload = impl_->force_reload;
    impl_->force_reload = false;
    impl_->file_stamp = current_stamp;
  }

  if (!force_reload && LoadCachedSlides(metadata_path, current_stamp, deck_data)) {
    blog(LOG_INFO, "[PPTBridge SK] Reused cached Windows slide export for '%s'", impl_->path.c_str());
  } else {
    std::string output;
    int exit_code = -1;
    {
      std::lock_guard<std::mutex> script_lock(impl_->script_mutex);
        RunPowerShellMode(L"export", Utf8ToWide(impl_->path), impl_->cache_root.wstring(), 0, output, exit_code);
    }

    if (exit_code != 0 || !ParseExportOutput(output, deck_data, load_error)) {
      if (load_error.empty()) {
        load_error = output.empty() ? "PowerPoint export failed on Windows." : output;
      }
    } else {
      SaveCachedSlides(metadata_path, current_stamp, deck_data.slides, deck_data.media_by_slide);
    }
  }

  LiveSnapshot live_snapshot;
  std::string live_error;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->slides = std::move(deck_data.slides);
    impl_->media_by_slide = std::move(deck_data.media_by_slide);
    if (impl_->media_by_slide.size() < impl_->slides.size()) {
      impl_->media_by_slide.resize(impl_->slides.size());
    }
    impl_->loaded = !impl_->slides.empty();
    impl_->loading = false;
    impl_->live_ready = false;
    impl_->live_window_title.clear();
    impl_->current_index = 0;
    impl_->current_media_triggered = false;
    impl_->last_error = load_error;
    impl_->state_version += 1;
  }

  if (!load_error.empty()) {
    blog(LOG_WARNING, "[PPTBridge SK] Windows export failed for '%s': %s", impl_->path.c_str(), load_error.c_str());
    return;
  }

  bool live_enabled = false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    live_enabled = impl_->live_enabled;
  }

  if (live_enabled) {
    std::string output;
    int exit_code = -1;
    {
      std::lock_guard<std::mutex> script_lock(impl_->script_mutex);
      RunPowerShellMode(L"live-start", Utf8ToWide(impl_->path), impl_->cache_root.wstring(), 0, output, exit_code);
    }

    if (exit_code == 0 && ParseLiveSnapshot(output, live_snapshot, live_error) && live_snapshot.running) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->live_ready = true;
      impl_->live_window_title = live_snapshot.window_title;
      if (!impl_->slides.empty() && live_snapshot.current_slide > 0) {
        impl_->current_index = std::min(live_snapshot.current_slide - 1, impl_->slides.size() - 1);
      }
      impl_->current_media_triggered = false;
      impl_->timer_started_at = std::chrono::steady_clock::now();
      impl_->state_version += 1;
      impl_->last_error.clear();
    } else if (!live_error.empty()) {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->last_error = live_error;
      impl_->state_version += 1;
    }
  }
}

}  // namespace pptbridge

#endif  // _WIN32
