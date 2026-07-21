param(
  [Parameter(Mandatory = $true)]
  [string]$DeckPath,

  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DeckPath -PathType Leaf)) {
  throw "Deck does not exist: $DeckPath"
}
$DeckPath = (Resolve-Path -LiteralPath $DeckPath).Path

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PPTBridgeWindowProbe {
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr param);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr param);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr param);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hwnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetParent(IntPtr hwnd);

    public static string ClassName(IntPtr hwnd) {
        StringBuilder value = new StringBuilder(512);
        GetClassName(hwnd, value, value.Capacity);
        return value.ToString();
    }

    public static string WindowText(IntPtr hwnd) {
        StringBuilder value = new StringBuilder(2048);
        GetWindowText(hwnd, value, value.Capacity);
        return value.ToString();
    }
}
'@

function Release-ComObjectQuietly {
  param($Value)
  if ($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
  }
}

function Get-WindowRecord {
  param([IntPtr]$Hwnd, [string]$Scope, [int]$Depth)

  [uint32]$windowProcessId = 0
  [void][PPTBridgeWindowProbe]::GetWindowThreadProcessId($Hwnd, [ref]$windowProcessId)
  $rect = New-Object PPTBridgeWindowProbe+RECT
  $client = New-Object PPTBridgeWindowProbe+RECT
  [void][PPTBridgeWindowProbe]::GetWindowRect($Hwnd, [ref]$rect)
  [void][PPTBridgeWindowProbe]::GetClientRect($Hwnd, [ref]$client)
  $parent = [PPTBridgeWindowProbe]::GetParent($Hwnd)

  return [pscustomobject]@{
    scope = $Scope
    depth = $Depth
    hwnd = ("0x{0:X}" -f $Hwnd.ToInt64())
    parent = ("0x{0:X}" -f $parent.ToInt64())
    pid = [int]$windowProcessId
    visible = [PPTBridgeWindowProbe]::IsWindowVisible($Hwnd)
    class = [PPTBridgeWindowProbe]::ClassName($Hwnd)
    title = [PPTBridgeWindowProbe]::WindowText($Hwnd)
    x = $rect.Left
    y = $rect.Top
    width = $rect.Right - $rect.Left
    height = $rect.Bottom - $rect.Top
    clientWidth = $client.Right - $client.Left
    clientHeight = $client.Bottom - $client.Top
  }
}

$app = $null
$presentation = $null
$show = $null
$settings = $null
$view = $null
$records = [Collections.Generic.List[object]]::new()

try {
  $app = New-Object -ComObject PowerPoint.Application
  $app.Visible = -1
  $presentation = $app.Presentations.Open($DeckPath, $true, $false, $true)
  $settings = $presentation.SlideShowSettings
  $settings.ShowType = 2
  $settings.LoopUntilStopped = $false
  $show = $settings.Run()
  Start-Sleep -Seconds 3
  $view = $show.View

  [uint32]$powerPointPid = 0
  [void][PPTBridgeWindowProbe]::GetWindowThreadProcessId([IntPtr][int64]$app.HWND, [ref]$powerPointPid)

  $topLevel = [Collections.Generic.List[IntPtr]]::new()
  $topCallback = [PPTBridgeWindowProbe+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$param)
    [uint32]$windowProcessId = 0
    [void][PPTBridgeWindowProbe]::GetWindowThreadProcessId($hwnd, [ref]$windowProcessId)
    if ($windowProcessId -eq $powerPointPid) {
      $topLevel.Add($hwnd)
    }
    return $true
  }
  [void][PPTBridgeWindowProbe]::EnumWindows($topCallback, [IntPtr]::Zero)

  foreach ($top in $topLevel) {
    $records.Add((Get-WindowRecord $top "top" 0))
    $childCallback = [PPTBridgeWindowProbe+EnumWindowsProc]{
      param([IntPtr]$hwnd, [IntPtr]$param)
      $records.Add((Get-WindowRecord $hwnd "child" 1))
      return $true
    }
    [void][PPTBridgeWindowProbe]::EnumChildWindows($top, $childCallback, [IntPtr]::Zero)
  }

  $clickIndex = -1
  $clickCount = -1
  try { $clickIndex = [int]$view.GetClickIndex() } catch {}
  try { $clickCount = [int]$view.GetClickCount() } catch {}
  $slideTwoBefore = $null
  $slideTwoAfter = $null
  try {
    $view.GotoSlide(2, 0)
    Start-Sleep -Milliseconds 500
    $slideTwoBefore = [pscustomobject]@{
      slide = [int]$view.CurrentShowPosition
      clickIndex = [int]$view.GetClickIndex()
      clickCount = [int]$view.GetClickCount()
    }
    $view.Next()
    Start-Sleep -Milliseconds 500
    $slideTwoAfter = [pscustomobject]@{
      slide = [int]$view.CurrentShowPosition
      clickIndex = [int]$view.GetClickIndex()
      clickCount = [int]$view.GetClickCount()
    }
  } catch {}
  $payload = [pscustomobject]@{
    deck = $DeckPath
    processId = [int]$powerPointPid
    slideShowHwnd = if ($null -ne $show) { "0x{0:X}" -f [int64]$show.HWND } else { "" }
    viewMembers = @($view | Get-Member | Where-Object { $_.Name -match "Click|Next|Previous|Goto" } | Select-Object Name,MemberType,Definition)
    clickIndex = $clickIndex
    clickCount = $clickCount
    slideTwoBefore = $slideTwoBefore
    slideTwoAfter = $slideTwoAfter
    windows = @($records)
  }
  $json = $payload | ConvertTo-Json -Depth 5
  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
  }
  $json
} finally {
  if ($null -ne $show) {
    try { $show.View.Exit() } catch {}
  }
  if ($null -ne $presentation) {
    try { $presentation.Close() } catch {}
  }
  if ($null -ne $app) {
    try { $app.Quit() } catch {}
  }
  Release-ComObjectQuietly $settings
  Release-ComObjectQuietly $view
  Release-ComObjectQuietly $show
  Release-ComObjectQuietly $presentation
  Release-ComObjectQuietly $app
}
