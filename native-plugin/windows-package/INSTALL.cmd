@echo off
setlocal
cd /d "%~dp0"
set "PPTBRIDGE_INSTALLER=%~f0"
set "PPTBRIDGE_OBS_ROOT_ARG=%~1"
if /I "%~2"=="--no-pause" set "PPTBRIDGE_INSTALLER_NO_PAUSE=1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -Command "$self=$env:PPTBRIDGE_INSTALLER; $raw=[IO.File]::ReadAllText($self); $marker='### POWERSHELL_INSTALLER ###'; $idx=$raw.LastIndexOf($marker); if($idx -lt 0){throw 'Installer payload missing.'}; $payload=$raw.Substring($idx + $marker.Length); $tmp=Join-Path $env:TEMP ('pptbridge-install-' + [guid]::NewGuid().ToString('N') + '.ps1'); [IO.File]::WriteAllText($tmp,$payload,[Text.Encoding]::UTF8); & powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File $tmp; $code=$LASTEXITCODE; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; exit $code"
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" (
  echo.
  echo Installation failed with exit code %exitCode%.
  echo If you need help, send the OBS log and a screenshot of this window.
  if not "%PPTBRIDGE_INSTALLER_NO_PAUSE%"=="1" pause
  exit /b %exitCode%
)
if not "%PPTBRIDGE_INSTALLER_NO_PAUSE%"=="1" pause
exit /b %exitCode%

### POWERSHELL_INSTALLER ###
$ErrorActionPreference = "Stop"

trap {
  Write-Host ""
  Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "== $Message =="
}

function Get-Sha256Hash {
  param([string]$Path)

  $stream = [IO.File]::Open(
    $Path,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "")
  } finally {
    $sha256.Dispose()
    $stream.Dispose()
  }
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
  foreach ($root in @($programFiles, $programFilesX86)) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $rootPath = [IO.Path]::GetFullPath($root).TrimEnd('\')
    if ($fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }
  return $false
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
  if (-not [string]::IsNullOrWhiteSpace($argRoot)) {
    if (Test-ObsRoot $argRoot) {
      return [IO.Path]::GetFullPath($argRoot)
    }
    throw "The selected OBS folder is not valid: $argRoot. It must contain bin\64bit\obs64.exe. No other OBS installation was changed."
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
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $env:ComSpec
  $noPauseArgument = if ($env:PPTBRIDGE_INSTALLER_NO_PAUSE -eq "1") { " --no-pause" } else { "" }
  $startInfo.Arguments = '/d /s /c ""' + $env:PPTBRIDGE_INSTALLER + '" "' + $obsRoot + '"' + $noPauseArgument + '"'
  $startInfo.Verb = "runas"
  $startInfo.UseShellExecute = $true
  try {
    $adminProcess = [Diagnostics.Process]::Start($startInfo)
  } catch [ComponentModel.Win32Exception] {
    if ($_.Exception.NativeErrorCode -eq 1223) {
      throw "Administrator permission was cancelled. Run INSTALL.cmd again and choose Yes when Windows asks."
    }
    throw
  }
  if (-not $adminProcess) {
    throw "Windows could not start the installer with administrator permission."
  }
  $adminProcess.WaitForExit()
  exit $adminProcess.ExitCode
}

Write-Step "Checking OBS"
Stop-ObsIfNeeded $obsRoot

Write-Step "Installing plugin"
$targetPluginDir = Join-Path $obsRoot "obs-plugins\64bit"
$targetDataDir = Join-Path $obsRoot "data\obs-plugins\pptbridge-obs"
$targetDll = Join-Path $targetPluginDir "pptbridge-obs.dll"
$targetDataParent = Split-Path -Parent $targetDataDir
$installId = [guid]::NewGuid().ToString("N")
$stagedDll = Join-Path $targetPluginDir ("pptbridge-obs.dll.install-" + $installId)
$stagedDataDir = Join-Path $targetDataParent ("pptbridge-obs.install-" + $installId)
$backupDll = Join-Path $targetPluginDir ("pptbridge-obs.dll.backup-" + $installId)
$backupDataDir = Join-Path $targetDataParent ("pptbridge-obs.backup-" + $installId)

New-Item -ItemType Directory -Force -Path $targetPluginDir | Out-Null
New-Item -ItemType Directory -Force -Path $targetDataParent | Out-Null

$oldDllMoved = $false
$oldDataMoved = $false
$newDllPlaced = $false
$newDataPlaced = $false
$sourceHash = Get-Sha256Hash $sourceDll

try {
  # Stage and verify every new file before changing the working OBS plugin.
  Copy-Item -LiteralPath $sourceDll -Destination $stagedDll -Force
  New-Item -ItemType Directory -Path $stagedDataDir | Out-Null
  Get-ChildItem -LiteralPath $sourceData | Copy-Item -Destination $stagedDataDir -Recurse -Force

  $stagedLocale = Join-Path $stagedDataDir "locale\en-US.ini"
  $stagedLocaleGb = Join-Path $stagedDataDir "locale\en-GB.ini"
  if (-not (Test-Path -LiteralPath $stagedLocale) -or
      -not (Test-Path -LiteralPath $stagedLocaleGb)) {
    throw "Install verification failed: the required OBS locale files are missing from the download."
  }
  $stagedHash = Get-Sha256Hash $stagedDll
  if ($sourceHash -ne $stagedHash) {
    throw "Install verification failed while preparing the plugin DLL."
  }

  try {
    Unblock-File -LiteralPath $stagedDll -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $stagedDataDir -Recurse -File -ErrorAction SilentlyContinue |
      Unblock-File -ErrorAction SilentlyContinue
  } catch {
  }

  if (Test-Path -LiteralPath $targetDll) {
    Move-Item -LiteralPath $targetDll -Destination $backupDll
    $oldDllMoved = $true
  }
  if (Test-Path -LiteralPath $targetDataDir) {
    Move-Item -LiteralPath $targetDataDir -Destination $backupDataDir
    $oldDataMoved = $true
  }

  Move-Item -LiteralPath $stagedDll -Destination $targetDll
  $newDllPlaced = $true
  Move-Item -LiteralPath $stagedDataDir -Destination $targetDataDir
  $newDataPlaced = $true

  $locale = Join-Path $targetDataDir "locale\en-US.ini"
  $localeGb = Join-Path $targetDataDir "locale\en-GB.ini"
  if (-not (Test-Path -LiteralPath $targetDll) -or
      -not (Test-Path -LiteralPath $locale) -or
      -not (Test-Path -LiteralPath $localeGb)) {
    throw "Install verification failed after activating the new plugin files."
  }
  $targetHash = Get-Sha256Hash $targetDll
  if ($sourceHash -ne $targetHash) {
    throw "Install verification failed: the installed plugin does not match the downloaded plugin file."
  }
} catch {
  $installFailure = $_.Exception.Message
  $rollbackErrors = [System.Collections.Generic.List[string]]::new()

  foreach ($entry in @(
      @{ Placed = $newDataPlaced; Path = $targetDataDir; Recursive = $true },
      @{ Placed = $newDllPlaced; Path = $targetDll; Recursive = $false }
    )) {
    if ($entry.Placed -and (Test-Path -LiteralPath $entry.Path)) {
      try {
        Remove-Item -LiteralPath $entry.Path -Force -Recurse:$entry.Recursive
      } catch {
        $rollbackErrors.Add($_.Exception.Message) | Out-Null
      }
    }
  }

  foreach ($entry in @(
      @{ Moved = $oldDllMoved; Backup = $backupDll; Target = $targetDll },
      @{ Moved = $oldDataMoved; Backup = $backupDataDir; Target = $targetDataDir }
    )) {
    if ($entry.Moved -and (Test-Path -LiteralPath $entry.Backup)) {
      try {
        Move-Item -LiteralPath $entry.Backup -Destination $entry.Target
      } catch {
        $rollbackErrors.Add($_.Exception.Message) | Out-Null
      }
    }
  }

  if ($rollbackErrors.Count -gt 0) {
    throw "Installation failed: $installFailure Previous plugin files could not be fully restored: $($rollbackErrors -join '; ')"
  }
  throw "Installation failed safely; the previous plugin was restored. $installFailure"
} finally {
  Remove-Item -LiteralPath $stagedDll -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stagedDataDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Backups are removed only after the new DLL and both locale files pass verification.
Remove-Item -LiteralPath $backupDll -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $backupDataDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Step "Done"
Write-Host "PPTBridge SK was installed successfully."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Start OBS Studio."
Write-Host "2. In Sources, click + and choose PPTBridge SK Slide."
Write-Host "3. Select a PDF or PowerPoint file."
Write-Host "4. PDFs load directly. For PowerPoint, use START to open live mode and STOP to close it."
Write-Host "5. For a stage clicker while using other apps, enable Tools > PPTBridge SK: Spotlight/Clicker Capture On/Off."
Write-Host ""
Write-Host "Clicker routing: the clicker controls only visible PPTBridge sources in the current OBS Program scene."
Write-Host ""
Write-Host "You can close this window."
