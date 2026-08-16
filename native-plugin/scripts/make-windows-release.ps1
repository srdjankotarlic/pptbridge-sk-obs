param(
  [string]$Version = "0.5.10",
  [string]$Configuration = "Release",
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [string]$PackageName = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
  $BuildDir = Join-Path $pluginRoot "build-win"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $pluginRoot "release"
}
if ([string]::IsNullOrWhiteSpace($PackageName)) {
  $PackageName = "pptbridge-obs-windows-x64-v$Version"
}

$dllCandidates = @(
  (Join-Path $BuildDir "bundle\$Configuration\pptbridge-obs.dll"),
  (Join-Path $BuildDir "bundle\pptbridge-obs.dll"),
  (Join-Path $BuildDir "$Configuration\pptbridge-obs.dll")
)
$dllPath = $dllCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $dllPath) {
  throw "Built Windows DLL not found. Build first with: cmake --build native-plugin/build-win --config $Configuration"
}

$templateDir = Join-Path $pluginRoot "windows-package"
$installer = Join-Path $templateDir "INSTALL.cmd"
$readme = Join-Path $templateDir "README.txt"
$dataDir = Join-Path $pluginRoot "data"
foreach ($required in @($installer, $readme, $dataDir)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Missing release input: $required"
  }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stagingRoot = Join-Path $OutputDir "staging"
$staging = Join-Path $stagingRoot $PackageName
$zipPath = Join-Path $OutputDir "$PackageName.zip"
$shaPath = "$zipPath.sha256"

$resolvedOutput = [IO.Path]::GetFullPath($OutputDir).TrimEnd('\') + '\'
$resolvedStaging = [IO.Path]::GetFullPath($staging)
if (-not $resolvedStaging.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe staging path outside the release output directory: $resolvedStaging"
}

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $staging "obs-plugins\64bit") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $staging "data\obs-plugins\pptbridge-obs") | Out-Null

Copy-Item -LiteralPath $installer -Destination (Join-Path $staging "INSTALL.cmd") -Force
Copy-Item -LiteralPath $readme -Destination (Join-Path $staging "README.txt") -Force
Copy-Item -LiteralPath $dllPath -Destination (Join-Path $staging "obs-plugins\64bit\pptbridge-obs.dll") -Force
Get-ChildItem -LiteralPath $dataDir | Copy-Item -Destination (Join-Path $staging "data\obs-plugins\pptbridge-obs") -Recurse -Force

$files = @(Get-ChildItem -LiteralPath $staging -Recurse -File)
if ($files.Count -ne 5) {
  $list = ($files | ForEach-Object { $_.FullName.Substring($staging.Length + 1) }) -join "`n"
  throw "Unexpected Windows package file count: $($files.Count). Files:`n$list"
}

$forbiddenPattern = "codex|openai|ai assistant|source zip|handoff|beta|prerelease"
$badMatches = @(Select-String -LiteralPath ($files | Select-Object -ExpandProperty FullName) -Pattern $forbiddenPattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
if ($badMatches.Count -gt 0) {
  $details = ($badMatches | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line)" }) -join "`n"
  throw "Forbidden public-package wording found:`n$details"
}

Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $shaPath -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
Set-Content -LiteralPath $shaPath -Value "$hash  $(Split-Path -Leaf $zipPath)" -Encoding ASCII

[pscustomobject]@{
  Zip = $zipPath
  Sha256 = $hash
  Sha256File = $shaPath
  Size = (Get-Item -LiteralPath $zipPath).Length
  FileCount = $files.Count
}
