@echo off
setlocal
cd /d "%~dp0"
set "PPTBRIDGE_INSTALLER=%~f0"
set "PPTBRIDGE_OBS_ROOT_ARG=%~1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -Command "$self=$env:PPTBRIDGE_INSTALLER; $raw=[IO.File]::ReadAllText($self); $marker='### POWERSHELL_INSTALLER ###'; $idx=$raw.LastIndexOf($marker); if($idx -lt 0){throw 'Installer payload missing.'}; $payload=$raw.Substring($idx + $marker.Length); $tmp=Join-Path $env:TEMP ('pptbridge-install-' + [guid]::NewGuid().ToString('N') + '.ps1'); [IO.File]::WriteAllText($tmp,$payload,[Text.Encoding]::UTF8); & powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File $tmp; $code=$LASTEXITCODE; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; exit $code"
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" (
  echo.
  echo Installation failed with exit code %exitCode%.
  echo If you need help, send the OBS log and a screenshot of this window.
  pause
  exit /b %exitCode%
)
if not "%PPTBRIDGE_INSTALLER_NO_PAUSE%"=="1" pause
exit /b %exitCode%

### POWERSHELL_INSTALLER ###
$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "== $Message =="
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-RequiresAdministrator {
  param([string]$Path)

  $programFiles = [Environment]::GetFolderPath("ProgramFiles")
  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
  $fullPath = [IO.Path]::GetFullPath($Path)
  return ($programFiles -and $fullPath.StartsWith($programFiles, [StringComparison]::OrdinalIgnoreCase)) -or
    ($programFilesX86 -and $fullPath.StartsWith($programFilesX86, [StringComparison]::OrdinalIgnoreCase))
}

function Test-ObsRoot {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }
  $exe = Join-Path $Path "bin\64bit\obs64.exe"
  return Test-Path -LiteralPath $exe
}

function Get-RegistryObsRoots {
  $roots = [System.Collections.Generic.List[string]]::new()
  foreach ($base in @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )) {
    Get-ItemProperty -Path $base -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -like "OBS Studio*" } |
      ForEach-Object {
        if ($_.InstallLocation) {
          $roots.Add([string]$_.InstallLocation) | Out-Null
        } elseif ($_.UninstallString -match '^"([^"]+)') {
          $candidate = Split-Path -Parent (Split-Path -Parent $Matches[1])
          $roots.Add($candidate) | Out-Null
        }
      }
  }
  return @($roots | Select-Object -Unique)
}

function Find-ObsRoot {
  $argRoot = $env:PPTBRIDGE_OBS_ROOT_ARG
  if (Test-ObsRoot $argRoot) {
    return [IO.Path]::GetFullPath($argRoot)
  }

  $candidates = [System.Collections.Generic.List[string]]::new()
  foreach ($root in Get-RegistryObsRoots) {
    $candidates.Add($root) | Out-Null
  }
  foreach ($root in @(
    (Join-Path ([Environment]::GetFolderPath("ProgramFiles")) "obs-studio"),
    (Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "obs-studio")
  )) {
    $candidates.Add($root) | Out-Null
  }

  $valid = @($candidates | Where-Object { Test-ObsRoot $_ } | Select-Object -Unique)
  if ($valid.Count -eq 1) {
    return [IO.Path]::GetFullPath($valid[0])
  }
  if ($valid.Count -gt 1) {
    Write-Host "Found more than one OBS installation:"
    for ($i = 0; $i -lt $valid.Count; $i++) {
      Write-Host ("  {0}. {1}" -f ($i + 1), $valid[$i])
    }
    $choice = Read-Host "Type the number to install there, or press Enter to choose a folder"
    if ($choice -match '^\d+$') {
      $index = [int]$choice - 1
      if ($index -ge 0 -and $index -lt $valid.Count) {
        return [IO.Path]::GetFullPath($valid[$index])
      }
    }
  }

  Add-Type -AssemblyName System.Windows.Forms
  $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
  $dialog.Description = "Select your OBS Studio folder. It should contain bin\64bit\obs64.exe."
  $dialog.ShowNewFolderButton = $false
  try {
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-ObsRoot $dialog.SelectedPath)) {
      return [IO.Path]::GetFullPath($dialog.SelectedPath)
    }
  } finally {
    $dialog.Dispose()
  }

  throw "OBS Studio folder was not found. Install 64-bit OBS Studio first, or run: INSTALL.cmd ""C:\Path\To\obs-studio"""
}

function Get-TargetObsProcesses {
  param([string]$ObsRoot)

  $targetExe = [IO.Path]::GetFullPath((Join-Path $ObsRoot "bin\64bit\obs64.exe"))
  return @(Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object {
    try {
      [IO.Path]::GetFullPath($_.Path) -ieq $targetExe
    } catch {
      $false
    }
  })
}

function Stop-ObsIfNeeded {
  param([string]$ObsRoot)

  $obsProcesses = @(Get-TargetObsProcesses $ObsRoot)
  if ($obsProcesses.Count -eq 0) {
    return
  }

  Write-Host "OBS is currently running."
  Write-Host "Close OBS now so the plugin DLL can be replaced."
  $answer = Read-Host "Type Y to let this installer close OBS automatically, or press Enter after you close OBS yourself"
  if ($answer -match '^[Yy]') {
    foreach ($process in $obsProcesses) {
      try { [void]$process.CloseMainWindow() } catch {}
    }
    $gracefulDeadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $gracefulDeadline -and @(Get-TargetObsProcesses $ObsRoot).Count -gt 0) {
      Start-Sleep -Milliseconds 500
    }
    $remaining = @(Get-TargetObsProcesses $ObsRoot)
    if ($remaining.Count -gt 0) {
      Write-Host "OBS did not close in time; finishing the close now."
      $remaining | Stop-Process -Force
    }
  }

  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    if (@(Get-TargetObsProcesses $ObsRoot).Count -eq 0) {
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw "OBS is still running. Close OBS and run INSTALL.cmd again."
}

Write-Host "PPTBridge SK for OBS - Windows installer"
Write-Host "This installs the PPTBridge SK OBS plugin into 64-bit OBS Studio."

$scriptRoot = Split-Path -Parent $env:PPTBRIDGE_INSTALLER
$sourceDll = Join-Path $scriptRoot "obs-plugins\64bit\pptbridge-obs.dll"
$sourceData = Join-Path $scriptRoot "data\obs-plugins\pptbridge-obs"

if (-not (Test-Path -LiteralPath $sourceDll)) {
  throw "Missing plugin file: $sourceDll. Extract the zip first, then run INSTALL.cmd from the extracted folder."
}
if (-not (Test-Path -LiteralPath $sourceData)) {
  throw "Missing plugin data folder: $sourceData. Extract the zip first, then run INSTALL.cmd from the extracted folder."
}

Write-Step "Finding OBS Studio"
$obsRoot = Find-ObsRoot
Write-Host "OBS folder: $obsRoot"

if ((Test-RequiresAdministrator $obsRoot) -and -not (Test-IsAdministrator)) {
  Write-Host "Administrator permission is needed to install into this OBS folder."
  $argList = "/c ""$env:PPTBRIDGE_INSTALLER"" ""$obsRoot"""
  $adminProcess = Start-Process -FilePath "cmd.exe" -ArgumentList $argList -Verb RunAs -Wait -PassThru
  exit $adminProcess.ExitCode
}

Write-Step "Checking OBS"
Stop-ObsIfNeeded $obsRoot

Write-Step "Installing plugin"
$targetPluginDir = Join-Path $obsRoot "obs-plugins\64bit"
$targetDataDir = Join-Path $obsRoot "data\obs-plugins\pptbridge-obs"
$targetDll = Join-Path $targetPluginDir "pptbridge-obs.dll"

New-Item -ItemType Directory -Force -Path $targetPluginDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetDataDir) | Out-Null

Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force
if (Test-Path -LiteralPath $targetDataDir) {
  Remove-Item -LiteralPath $targetDataDir -Recurse -Force
}
Copy-Item -LiteralPath $sourceData -Destination (Split-Path -Parent $targetDataDir) -Recurse -Force

try {
  Unblock-File -LiteralPath $targetDll -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $targetDataDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
} catch {
}

$locale = Join-Path $targetDataDir "locale\en-US.ini"
if (-not (Test-Path -LiteralPath $targetDll)) {
  throw "Install verification failed: DLL was not copied to $targetDll"
}
if (-not (Test-Path -LiteralPath $locale)) {
  throw "Install verification failed: locale file was not copied to $locale"
}

Write-Step "Done"
Write-Host "PPTBridge SK was installed successfully."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Start OBS Studio."
Write-Host "2. In Sources, click + and choose PPTBridge SK Slide."
Write-Host "3. Select your PowerPoint file."
Write-Host "4. Use START to open PowerPoint live mode and STOP to close it."
Write-Host "5. For a stage clicker while using other apps, enable Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off."
Write-Host ""
Write-Host "Clicker routing: the clicker controls only visible PPTBridge sources in the current OBS Program scene."
Write-Host ""
Write-Host "You can close this window."
