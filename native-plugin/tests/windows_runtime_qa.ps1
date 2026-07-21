param(
  [Parameter(Mandatory = $true)]
  [string]$DeckPlain,
  [Parameter(Mandatory = $true)]
  [string]$DeckAnimation,
  [Parameter(Mandatory = $true)]
  [string]$DeckMedia,
  [Parameter(Mandatory = $true)]
  [string]$ArtifactsDir,
  [string]$WebSocketPassword = "FdtsCFFP61K1HZY9",
  [int]$OscPort = 57130,
  [int]$OscFeedbackPort = 57131,
  [string]$ClickerProbePath = "",
  [string]$RunLabel = "windows-runtime",
  [int]$StartTimeoutSeconds = 55,
  [int]$StopTimeoutSeconds = 30,
  [int]$StressCycles = 10,
  [string[]]$CompatibilityDecks = @(),
  [int]$CompatibilityStartTimeoutSeconds = 330
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ([string]::IsNullOrWhiteSpace($ClickerProbePath)) {
  $ClickerProbePath = Join-Path $PSScriptRoot "windows_clicker_focus_probe.ps1"
}

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PptBridgeQaWindow {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr parameter);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetWindowPos(
    IntPtr hWnd,
    IntPtr hWndInsertAfter,
    int x,
    int y,
    int cx,
    int cy,
    uint flags);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);

  public static IntPtr FindPowerPointSlideShowWindow(string deckName, string deckStem) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr hWnd, IntPtr parameter) {
      if (!IsWindowVisible(hWnd)) {
        return true;
      }
      var titleBuffer = new System.Text.StringBuilder(2048);
      var classBuffer = new System.Text.StringBuilder(256);
      GetWindowText(hWnd, titleBuffer, titleBuffer.Capacity);
      GetClassName(hWnd, classBuffer, classBuffer.Capacity);
      string title = titleBuffer.ToString();
      string className = classBuffer.ToString();
      bool powerpointClass = className.Equals("PPTFrameClass", StringComparison.OrdinalIgnoreCase) ||
        className.Equals("screenClass", StringComparison.OrdinalIgnoreCase);
      bool slideShowTitle = title.IndexOf("Slide Show", StringComparison.OrdinalIgnoreCase) >= 0 ||
        title.IndexOf("Slideshow", StringComparison.OrdinalIgnoreCase) >= 0;
      bool deckMatch = (!String.IsNullOrEmpty(deckName) &&
          title.IndexOf(deckName, StringComparison.OrdinalIgnoreCase) >= 0) ||
        (!String.IsNullOrEmpty(deckStem) &&
          title.IndexOf(deckStem, StringComparison.OrdinalIgnoreCase) >= 0);
      if (powerpointClass && slideShowTitle && deckMatch) {
        found = hWnd;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@

function Receive-ObsMessage {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [int]$TimeoutMilliseconds = 0
  )

  $buffer = New-Object byte[] 65536
  $segment = [System.ArraySegment[byte]]::new($buffer)
  $stream = [System.IO.MemoryStream]::new()
  $cts = $null
  $token = [System.Threading.CancellationToken]::None
  if ($TimeoutMilliseconds -gt 0) {
    $cts = [System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter($TimeoutMilliseconds)
    $token = $cts.Token
  }
  try {
    do {
      try {
        $result = $Socket.ReceiveAsync($segment, $token).GetAwaiter().GetResult()
      } catch [System.OperationCanceledException] {
        return $null
      } catch {
        if ($_.Exception.InnerException -is [System.OperationCanceledException]) {
          return $null
        }
        throw
      }
      if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
        throw "obs-websocket closed the connection."
      }
      if ($result.Count -gt 0) {
        $stream.Write($buffer, 0, $result.Count)
      }
    } while (-not $result.EndOfMessage)

    $json = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    if ([string]::IsNullOrWhiteSpace($json)) {
      throw "Received an empty obs-websocket message."
    }
    return $json | ConvertFrom-Json
  } finally {
    $stream.Dispose()
    if ($cts) {
      $cts.Dispose()
    }
  }
}

function Send-ObsMessage {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [hashtable]$Payload
  )

  $json = $Payload | ConvertTo-Json -Compress -Depth 40
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $segment = [System.ArraySegment[byte]]::new($bytes)
  $null = $Socket.SendAsync(
    $segment,
    [System.Net.WebSockets.WebSocketMessageType]::Text,
    $true,
    [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Connect-Obs {
  param(
    [string]$Password,
    [int]$EventSubscriptions = 0
  )

  $socket = [System.Net.WebSockets.ClientWebSocket]::new()
  $socket.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
  $null = $socket.ConnectAsync(
    [Uri]"ws://127.0.0.1:4455",
    [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

  $hello = Receive-ObsMessage $socket
  if ($hello.op -ne 0) {
    throw "Expected obs-websocket Hello, got op=$($hello.op)."
  }

  $identifyData = @{
    rpcVersion = 1
    eventSubscriptions = $EventSubscriptions
  }
  if ($hello.d.authentication) {
    $salt = [string]$hello.d.authentication.salt
    $challenge = [string]$hello.d.authentication.challenge
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $secretBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password + $salt))
      $secret = [Convert]::ToBase64String($secretBytes)
      $authBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($secret + $challenge))
      $identifyData.authentication = [Convert]::ToBase64String($authBytes)
    } finally {
      $sha.Dispose()
    }
  }

  Send-ObsMessage $socket @{
    op = 1
    d = $identifyData
  }
  $identified = Receive-ObsMessage $socket
  if ($identified.op -ne 2) {
    throw "Expected obs-websocket Identified, got op=$($identified.op)."
  }
  return $socket
}

function Invoke-ObsRequest {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$RequestType,
    [hashtable]$RequestData = @{}
  )

  $requestId = [Guid]::NewGuid().ToString("N")
  Send-ObsMessage $Socket @{
    op = 6
    d = @{
      requestType = $RequestType
      requestId = $requestId
      requestData = $RequestData
    }
  }

  do {
    $message = Receive-ObsMessage $Socket
  } while ($message.op -ne 7 -or $message.d.requestId -ne $requestId)

  if (-not $message.d.requestStatus.result) {
    $comment = if ($message.d.requestStatus.comment) {
      [string]$message.d.requestStatus.comment
    } else {
      "unknown error"
    }
    throw "OBS request '$RequestType' failed: $comment"
  }
  return $message.d.responseData
}

function Try-ObsRequest {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$RequestType,
    [hashtable]$RequestData = @{}
  )

  try {
    return Invoke-ObsRequest $Socket $RequestType $RequestData
  } catch {
    return $null
  }
}

function Get-FlatNumericMax {
  param($Value)

  $max = 0.0
  if ($null -eq $Value) {
    return $max
  }
  foreach ($item in @($Value)) {
    if (($item -is [System.Array]) -or
        (($item -is [System.Collections.IEnumerable]) -and -not ($item -is [string]))) {
      $nested = Get-FlatNumericMax $item
      if ($nested -gt $max) {
        $max = $nested
      }
    } else {
      $number = 0.0
      if ([double]::TryParse([string]$item, [ref]$number) -and $number -gt $max) {
        $max = $number
      }
    }
  }
  return $max
}

function Collect-ObsMeterPeak {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$InputName,
    [int]$Seconds
  )

  $deadline = (Get-Date).AddSeconds($Seconds)
  $peak = 0.0
  $matched = [System.Collections.Generic.Dictionary[string, double]]::new()
  while ((Get-Date) -lt $deadline) {
    $message = Receive-ObsMessage $Socket 1500
    if (-not $message -or $message.op -ne 5 -or $message.d.eventType -ne "InputVolumeMeters") {
      continue
    }
    foreach ($input in @($message.d.eventData.inputs)) {
      $name = [string]$input.inputName
      if ($name -ne $InputName -and -not $name.StartsWith("$InputName ")) {
        continue
      }
      $level = Get-FlatNumericMax $input.inputLevelsMul
      if ($level -gt $peak) {
        $peak = $level
      }
      if (-not $matched.ContainsKey($name) -or $level -gt $matched[$name]) {
        $matched[$name] = $level
      }
    }
  }
  return [pscustomobject]@{
    peak = $peak
    matchedInputs = @($matched.GetEnumerator() | Sort-Object Name | ForEach-Object {
      "{0}={1:N6}" -f $_.Key,$_.Value
    })
  }
}

function Add-Result {
  param(
    [System.Collections.Generic.List[object]]$Results,
    [string]$Name,
    [bool]$Passed,
    [string]$Details = ""
  )

  $Results.Add([pscustomobject]@{
    name = $Name
    passed = $Passed
    details = $Details
  }) | Out-Null
}

function Invoke-TestStep {
  param(
    [System.Collections.Generic.List[object]]$Results,
    [string]$Name,
    [scriptblock]$Body
  )

  try {
    $outcome = & $Body
    if ($outcome -is [hashtable]) {
      $passed = [bool]$outcome.passed
      $details = [string]$outcome.details
    } elseif ($outcome -is [bool]) {
      $passed = $outcome
      $details = ""
    } else {
      $passed = $true
      $details = [string]$outcome
    }
    Add-Result $Results $Name $passed $details
    return $passed
  } catch {
    Add-Result $Results $Name $false $_.Exception.Message
    return $false
  }
}

function Wait-Until {
  param(
    [scriptblock]$Condition,
    [int]$TimeoutSeconds = 20,
    [int]$PollMilliseconds = 350
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (& $Condition) {
      return $true
    }
    Start-Sleep -Milliseconds $PollMilliseconds
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Normalize-DeckPath {
  param([string]$Path)
  return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Release-ComObjectQuietly {
  param([object]$Value)
  if ($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
    try {
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Value)
    } catch {
    }
  }
}

function Get-PowerPointSessions {
  $sessions = @()
  $app = $null
  $windows = $null
  try {
    $app = [Runtime.InteropServices.Marshal]::GetActiveObject("PowerPoint.Application")
    $windows = $app.SlideShowWindows
    for ($index = 1; $index -le [int]$windows.Count; $index++) {
      $window = $null
      $presentation = $null
      $slides = $null
      $view = $null
      $currentSlide = $null
      try {
        $window = $windows.Item($index)
        $presentation = $window.Presentation
        $slides = $presentation.Slides
        $view = $window.View
        $path = ""
        try {
          $path = Normalize-DeckPath ([string]$presentation.FullName)
        } catch {
          $path = [string]$presentation.Name
        }
        $hwnd = 0
        try { $hwnd = [Int64]$window.HWND } catch {}
        if ($hwnd -eq 0) {
          $hwnd = [PptBridgeQaWindow]::FindPowerPointSlideShowWindow(
            [IO.Path]::GetFileName($path),
            [IO.Path]::GetFileNameWithoutExtension($path)).ToInt64()
        }
        $current = [int]$view.CurrentShowPosition
        try {
          $currentSlide = $view.Slide
          $current = [int]$currentSlide.SlideIndex
        } catch {
        }
        $clickIndex = 0
        $clickCount = 0
        try { $clickIndex = [int]$view.GetClickIndex() } catch {}
        try { $clickCount = [int]$view.GetClickCount() } catch {}
        $sessions += [pscustomobject]@{
          path = $path
          current = $current
          total = [int]$slides.Count
          hwnd = $hwnd
          state = [int]$view.State
          clickIndex = $clickIndex
          clickCount = $clickCount
        }
      } catch {
      } finally {
        Release-ComObjectQuietly $currentSlide
        Release-ComObjectQuietly $view
        Release-ComObjectQuietly $slides
        Release-ComObjectQuietly $presentation
        Release-ComObjectQuietly $window
      }
    }
  } catch {
  } finally {
    Release-ComObjectQuietly $windows
    Release-ComObjectQuietly $app
  }
  return @($sessions)
}

function Get-DeckSession {
  param([string]$DeckPath)
  $wanted = Normalize-DeckPath $DeckPath
  return @(Get-PowerPointSessions | Where-Object {
    [string]::Equals($_.path, $wanted, [StringComparison]::OrdinalIgnoreCase)
  } | Select-Object -First 1)
}

function Get-DeckSlide {
  param([string]$DeckPath)
  $session = @(Get-DeckSession $DeckPath)
  if ($session.Count -eq 0) {
    return 0
  }
  return [int]$session[0].current
}

function Close-DeckSlideShow {
  param([string]$DeckPath)

  $wanted = Normalize-DeckPath $DeckPath
  $app = $null
  $windows = $null
  try {
    $app = [Runtime.InteropServices.Marshal]::GetActiveObject("PowerPoint.Application")
    $windows = $app.SlideShowWindows
    for ($index = [int]$windows.Count; $index -ge 1; $index--) {
      $window = $null
      $presentation = $null
      $view = $null
      try {
        $window = $windows.Item($index)
        $presentation = $window.Presentation
        if ([string]::Equals(
          (Normalize-DeckPath ([string]$presentation.FullName)),
          $wanted,
          [StringComparison]::OrdinalIgnoreCase)) {
          $view = $window.View
          $view.Exit()
        }
      } catch {
      } finally {
        Release-ComObjectQuietly $view
        Release-ComObjectQuietly $presentation
        Release-ComObjectQuietly $window
      }
    }
  } catch {
  } finally {
    Release-ComObjectQuietly $windows
    Release-ComObjectQuietly $app
  }
}

function Wait-DeckStarted {
  param([string]$DeckPath, [int]$TimeoutSeconds = $StartTimeoutSeconds)
  return Wait-Until { @(Get-DeckSession $DeckPath).Count -eq 1 } -TimeoutSeconds $TimeoutSeconds
}

function Wait-DeckStopped {
  param([string]$DeckPath, [int]$TimeoutSeconds = $StopTimeoutSeconds)
  return Wait-Until { @(Get-DeckSession $DeckPath).Count -eq 0 } -TimeoutSeconds $TimeoutSeconds
}

function Wait-DeckSlide {
  param([string]$DeckPath, [int]$Slide, [int]$TimeoutSeconds = 12)
  return Wait-Until { (Get-DeckSlide $DeckPath) -eq $Slide } -TimeoutSeconds $TimeoutSeconds
}

function Press-InputButton {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$InputName,
    [string]$PropertyName
  )
  Invoke-ObsRequest $Socket "PressInputPropertiesButton" @{
    inputName = $InputName
    propertyName = $PropertyName
  } | Out-Null
}

function Set-InputSettings {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$InputName,
    [hashtable]$Settings,
    [bool]$Overlay = $true
  )
  Invoke-ObsRequest $Socket "SetInputSettings" @{
    inputName = $InputName
    inputSettings = $Settings
    overlay = $Overlay
  } | Out-Null
}

function Save-ObsScreenshot {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$SourceName,
    [string]$Path,
    [int]$Width = 1920,
    [int]$Height = 1080
  )
  Invoke-ObsRequest $Socket "SaveSourceScreenshot" @{
    sourceName = $SourceName
    imageFormat = "png"
    imageFilePath = $Path
    imageWidth = $Width
    imageHeight = $Height
    imageCompressionQuality = -1
  } | Out-Null
}

function Get-FileHashText {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return ""
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-ImageInfo {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ width = 0; height = 0; bytes = 0 }
  }
  $image = [Drawing.Image]::FromFile($Path)
  try {
    return [pscustomobject]@{
      width = [int]$image.Width
      height = [int]$image.Height
      bytes = [int64](Get-Item -LiteralPath $Path).Length
    }
  } finally {
    $image.Dispose()
  }
}

function Get-DarkPixelRatio {
  param([string]$Path, [int]$SampleStep = 16)
  if (-not (Test-Path -LiteralPath $Path)) {
    return 0.0
  }

  $bitmap = [Drawing.Bitmap]::FromFile($Path)
  try {
    $dark = 0
    $total = 0
    for ($y = 0; $y -lt $bitmap.Height; $y += $SampleStep) {
      for ($x = 0; $x -lt $bitmap.Width; $x += $SampleStep) {
        $pixel = $bitmap.GetPixel($x, $y)
        if ($pixel.R -le 12 -and $pixel.G -le 12 -and $pixel.B -le 12) {
          $dark += 1
        }
        $total += 1
      }
    }
    if ($total -eq 0) {
      return 0.0
    }
    return [double]$dark / [double]$total
  } finally {
    $bitmap.Dispose()
  }
}

function Send-OscNoArg {
  param([string]$Address, [int]$Port)

  $bytes = [Collections.Generic.List[byte]]::new()
  foreach ($value in @($Address, ",")) {
    foreach ($byte in [Text.Encoding]::ASCII.GetBytes($value)) {
      $bytes.Add($byte) | Out-Null
    }
    $bytes.Add(0) | Out-Null
    while (($bytes.Count % 4) -ne 0) {
      $bytes.Add(0) | Out-Null
    }
  }
  $client = [Net.Sockets.UdpClient]::new()
  try {
    [void]$client.Send($bytes.ToArray(), $bytes.Count, "127.0.0.1", $Port)
  } finally {
    $client.Dispose()
  }
}

function Receive-OscAddresses {
  param(
    [Net.Sockets.UdpClient]$Receiver,
    [string[]]$Expected,
    [int]$TimeoutSeconds = 6
  )

  $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $Receiver.Client.ReceiveTimeout = 350
  while ((Get-Date) -lt $deadline -and $found.Count -lt $Expected.Count) {
    try {
      $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
      $packet = $Receiver.Receive([ref]$remote)
      $end = [Array]::IndexOf($packet, [byte]0)
      if ($end -gt 0) {
        $address = [Text.Encoding]::ASCII.GetString($packet, 0, $end)
        if ($Expected -contains $address) {
          [void]$found.Add($address)
        }
      }
    } catch [Net.Sockets.SocketException] {
      if ($_.Exception.SocketErrorCode -ne [Net.Sockets.SocketError]::TimedOut) {
        throw
      }
    }
  }
  return @($found)
}

function Invoke-ClickerProbe {
  param([string]$Key)

  $raw = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $ClickerProbePath -Key $Key
  if ($LASTEXITCODE -ne 0) {
    throw "Clicker focus probe failed for $Key."
  }
  return ($raw | Out-String | ConvertFrom-Json)
}

function Resize-DeckWindow {
  param([string]$DeckPath, [int]$Width, [int]$Height)

  $session = @(Get-DeckSession $DeckPath)
  if ($session.Count -ne 1 -or $session[0].hwnd -eq 0) {
    return $false
  }
  return [PptBridgeQaWindow]::SetWindowPos(
    [IntPtr]$session[0].hwnd,
    [IntPtr]::Zero,
    80,
    80,
    $Width,
    $Height,
    0x0004)
}

function Get-DeckWindowRect {
  param([string]$DeckPath)
  $session = @(Get-DeckSession $DeckPath)
  if ($session.Count -ne 1 -or $session[0].hwnd -eq 0) {
    return $null
  }
  $rect = [PptBridgeQaWindow+RECT]::new()
  if (-not [PptBridgeQaWindow]::GetWindowRect([IntPtr]$session[0].hwnd, [ref]$rect)) {
    return $null
  }
  return [pscustomobject]@{
    width = $rect.Right - $rect.Left
    height = $rect.Bottom - $rect.Top
    left = $rect.Left
    top = $rect.Top
  }
}

foreach ($deck in @($DeckPlain, $DeckAnimation, $DeckMedia)) {
  if (-not (Test-Path -LiteralPath $deck -PathType Leaf)) {
    throw "Required QA deck does not exist: $deck"
  }
}
foreach ($deck in @($CompatibilityDecks)) {
  if (-not (Test-Path -LiteralPath $deck -PathType Leaf)) {
    throw "Compatibility QA deck does not exist: $deck"
  }
}
if (-not (Test-Path -LiteralPath $ClickerProbePath -PathType Leaf)) {
  throw "Clicker probe does not exist: $ClickerProbePath"
}

$DeckPlain = Normalize-DeckPath $DeckPlain
$DeckAnimation = Normalize-DeckPath $DeckAnimation
$DeckMedia = Normalize-DeckPath $DeckMedia
$CompatibilityDecks = @($CompatibilityDecks | ForEach-Object { Normalize-DeckPath $_ })
New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
$ArtifactsDir = Normalize-DeckPath $ArtifactsDir
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$prefix = "PPTBridge QA $RunLabel $stamp"
$results = [Collections.Generic.List[object]]::new()
$socket = $null
$createdInputs = [Collections.Generic.List[string]]::new()
$createdScenes = [Collections.Generic.List[string]]::new()
$unexpectedError = ""

$sceneA = "$prefix Program A"
$sceneB = "$prefix Program B"
$sceneAuto = "$prefix Auto"
$sceneInvalid = "$prefix Invalid"
$slideA = "$prefix Slide A"
$slideAlias = "$prefix Slide Alias"
$presenterA = "$prefix Presenter A"
$slideB = "$prefix Animation"
$slideMedia = "$prefix Media"
$slideAuto = "$prefix Auto Slide"
$slideCached = "$prefix Cached Slide"

$baseSlideSettings = @{
  pptx_path = $DeckPlain
  canvas_width = 1920
  canvas_height = 1080
  use_live_powerpoint = $false
  auto_start_live_powerpoint = $false
  close_live_powerpoint_on_shutdown = $true
  live_capture_resize_mode = "lock_canvas"
  audio_enabled = $true
  use_live_app_audio = $true
  auto_recover_live = $true
  audio_gain_db = 0.0
}

try {
  foreach ($deck in @($DeckPlain, $DeckAnimation, $DeckMedia)) {
    Close-DeckSlideShow $deck
  }
  Start-Sleep -Seconds 2

  $socket = Connect-Obs $WebSocketPassword
  $version = Invoke-ObsRequest $socket "GetVersion"
  Add-Result $results "obs-websocket connected" $true (
    "OBS={0}; websocket={1}; RPC={2}" -f $version.obsVersion,$version.obsWebSocketVersion,$version.rpcVersion)

  Invoke-ObsRequest $socket "SetStudioModeEnabled" @{ studioModeEnabled = $false } | Out-Null

  $kindList = Invoke-ObsRequest $socket "GetInputKindList"
  $inputKinds = @($kindList.inputKinds)
  Add-Result $results "Slide source kind is registered" ($inputKinds -contains "pptbridge_slide_source") ""
  Add-Result $results "Presenter source kind is registered" ($inputKinds -contains "pptbridge_presenter_source") ""

  foreach ($scene in @($sceneA, $sceneB, $sceneAuto, $sceneInvalid)) {
    Invoke-ObsRequest $socket "CreateScene" @{ sceneName = $scene } | Out-Null
    $createdScenes.Add($scene) | Out-Null
  }

  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneA
    inputName = $slideA
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $true
    inputSettings = $baseSlideSettings
  } | Out-Null
  $createdInputs.Add($slideA) | Out-Null

  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneA
    inputName = $presenterA
    inputKind = "pptbridge_presenter_source"
    sceneItemEnabled = $true
    inputSettings = @{
      pptx_path = $DeckPlain
      canvas_width = 1920
      canvas_height = 1080
      presenter_layout = "balanced"
      presenter_preview_scale_mode = "fit"
      presenter_show_cue_list = $true
      close_live_powerpoint_on_shutdown = $true
    }
  } | Out-Null
  $createdInputs.Add($presenterA) | Out-Null

  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneA } | Out-Null
  Start-Sleep -Seconds 9

  $staticShot = Join-Path $ArtifactsDir "$stamp-static-plain.png"
  Save-ObsScreenshot $socket $slideA $staticShot
  $staticInfo = Get-ImageInfo $staticShot
  Add-Result $results "Static PPTX renders at 1920x1080" (
    $staticInfo.width -eq 1920 -and $staticInfo.height -eq 1080 -and $staticInfo.bytes -gt 5000) (
    "{0}x{1}; {2} bytes" -f $staticInfo.width,$staticInfo.height,$staticInfo.bytes)

  $presenterShot = Join-Path $ArtifactsDir "$stamp-presenter-balanced.png"
  Save-ObsScreenshot $socket $presenterA $presenterShot
  $presenterInfo = Get-ImageInfo $presenterShot
  Add-Result $results "Presenter view renders notes/layout" (
    $presenterInfo.width -eq 1920 -and $presenterInfo.height -eq 1080 -and
    $presenterInfo.bytes -gt 5000 -and
    (Get-FileHashText $presenterShot) -ne (Get-FileHashText $staticShot)) (
    "{0}x{1}; {2} bytes" -f $presenterInfo.width,$presenterInfo.height,$presenterInfo.bytes)

  $cacheWatch = [Diagnostics.Stopwatch]::StartNew()
  $cachedSettings = $baseSlideSettings.Clone()
  $cachedSettings.use_live_app_audio = $false
  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneA
    inputName = $slideCached
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $false
    inputSettings = $cachedSettings
  } | Out-Null
  $createdInputs.Add($slideCached) | Out-Null
  Start-Sleep -Milliseconds 750
  $cachedShot = Join-Path $ArtifactsDir "$stamp-static-cached.png"
  Save-ObsScreenshot $socket $slideCached $cachedShot
  $cacheWatch.Stop()
  Add-Result $results "Same deck is reused from cache" (
    (Get-FileHashText $cachedShot) -eq (Get-FileHashText $staticShot) -and $cacheWatch.Elapsed.TotalSeconds -lt 5) (
    "elapsed={0:N2}s" -f $cacheWatch.Elapsed.TotalSeconds)

  $startWatch = [Diagnostics.Stopwatch]::StartNew()
  Press-InputButton $socket $presenterA "pptbridge_start_live_btn"
  $startedFromPresenter = Wait-DeckStarted $DeckPlain
  $startWatch.Stop()
  $slideSettingsAfterPresenterStart = Invoke-ObsRequest $socket "GetInputSettings" @{ inputName = $slideA }
  Add-Result $results "Presenter START enables matching Slide live source" (
    $startedFromPresenter -and [bool]$slideSettingsAfterPresenterStart.inputSettings.use_live_powerpoint) (
    "started={0}; slideLive={1}; elapsed={2:N2}s" -f
      $startedFromPresenter,$slideSettingsAfterPresenterStart.inputSettings.use_live_powerpoint,$startWatch.Elapsed.TotalSeconds)

  if ($startedFromPresenter) {
    Start-Sleep -Seconds 5
    $liveShot = Join-Path $ArtifactsDir "$stamp-live-plain.png"
    Save-ObsScreenshot $socket $slideA $liveShot
    $liveInfo = Get-ImageInfo $liveShot
    Add-Result $results "Live PowerPoint capture renders" (
      $liveInfo.width -eq 1920 -and $liveInfo.height -eq 1080 -and $liveInfo.bytes -gt 5000) (
      "{0}x{1}; {2} bytes" -f $liveInfo.width,$liveInfo.height,$liveInfo.bytes)
  }

  $plainStartSession = @(Get-DeckSession $DeckPlain)
  $plainSlideCount = if ($plainStartSession.Count -eq 1) { [int]$plainStartSession[0].total } else { 0 }
  $plainLastSlide = [Math]::Max(1, $plainSlideCount)

  Press-InputButton $socket $slideA "pptbridge_first_btn"
  [void](Wait-DeckSlide $DeckPlain 1)
  Press-InputButton $socket $slideA "pptbridge_next_btn"
  $nextWorked = Wait-DeckSlide $DeckPlain 2
  Press-InputButton $socket $slideA "pptbridge_prev_btn"
  $previousWorked = Wait-DeckSlide $DeckPlain 1
  Press-InputButton $socket $slideA "pptbridge_last_btn"
  $lastWorked = Wait-DeckSlide $DeckPlain $plainLastSlide 30
  Press-InputButton $socket $slideA "pptbridge_first_btn"
  $firstWorked = Wait-DeckSlide $DeckPlain 1
  Add-Result $results "Next Previous First Last controls navigate live deck" (
    $nextWorked -and $previousWorked -and $lastWorked -and $firstWorked) (
    "next={0}; previous={1}; last={2}; first={3}" -f $nextWorked,$previousWorked,$lastWorked,$firstWorked)

  Press-InputButton $socket $slideA "pptbridge_last_btn"
  $atFinalSlide = Wait-DeckSlide $DeckPlain $plainLastSlide 30
  $finalBuildsDrained = $false
  for ($guardIndex = 0; $guardIndex -lt 50 -and $atFinalSlide; $guardIndex++) {
    $guardSession = @(Get-DeckSession $DeckPlain)
    if ($guardSession.Count -ne 1 -or [int]$guardSession[0].current -ne $plainLastSlide) {
      break
    }
    if ([int]$guardSession[0].clickIndex -ge [int]$guardSession[0].clickCount) {
      $finalBuildsDrained = $true
      break
    }
    Press-InputButton $socket $slideA "pptbridge_next_btn"
    Start-Sleep -Milliseconds 600
  }
  if ($finalBuildsDrained) {
    Press-InputButton $socket $slideA "pptbridge_next_btn"
    Start-Sleep -Seconds 1
  }
  $finalGuardSession = @(Get-DeckSession $DeckPlain)
  $finalGuardWorked =
    $atFinalSlide -and $finalBuildsDrained -and
    $finalGuardSession.Count -eq 1 -and
    [int]$finalGuardSession[0].current -eq $plainLastSlide
  $returnedFromFinal = $false
  $previousAttempts = [Math]::Min(50, [Math]::Max(3, [int]$finalGuardSession[0].clickCount + 3))
  for ($previousIndex = 0; $previousIndex -lt $previousAttempts -and $finalGuardSession.Count -eq 1; $previousIndex++) {
    Press-InputButton $socket $slideA "pptbridge_prev_btn"
    $returnedFromFinal = Wait-Until {
      $slide = Get-DeckSlide $DeckPlain
      $slide -gt 0 -and $slide -lt $plainLastSlide
    } -TimeoutSeconds 2 -PollMilliseconds 150
    if ($returnedFromFinal) { break }
  }
  Add-Result $results "Final slide guard keeps slideshow open" (
    $finalGuardWorked -and $returnedFromFinal) (
    "session={0}; current={1}; buildsDrained={2}; previousAfterGuard={3}" -f
      $finalGuardSession.Count,
      $(if ($finalGuardSession.Count) { $finalGuardSession[0].current } else { 0 }),
      $finalBuildsDrained,
      $returnedFromFinal)

  Press-InputButton $socket $slideA "pptbridge_first_btn"
  [void](Wait-DeckSlide $DeckPlain 1)
  $beforeBlack = Join-Path $ArtifactsDir "$stamp-black-before.png"
  $duringBlack = Join-Path $ArtifactsDir "$stamp-black-on.png"
  $afterBlack = Join-Path $ArtifactsDir "$stamp-black-after.png"
  Save-ObsScreenshot $socket $slideA $beforeBlack
  Press-InputButton $socket $slideA "pptbridge_black_btn"
  Start-Sleep -Seconds 1
  Save-ObsScreenshot $socket $slideA $duringBlack
  Press-InputButton $socket $slideA "pptbridge_black_btn"
  Start-Sleep -Seconds 1
  Save-ObsScreenshot $socket $slideA $afterBlack
  $beforeBlackRatio = Get-DarkPixelRatio $beforeBlack
  $duringBlackRatio = Get-DarkPixelRatio $duringBlack
  $afterBlackRatio = Get-DarkPixelRatio $afterBlack
  Add-Result $results "Black screen toggles and restores output" (
    $beforeBlackRatio -lt 0.95 -and
    $duringBlackRatio -ge 0.99 -and
    $afterBlackRatio -lt 0.95) (
    "darkBefore={0:N3}; darkOn={1:N3}; darkAfter={2:N3}" -f
      $beforeBlackRatio,$duringBlackRatio,$afterBlackRatio)

  Press-InputButton $socket $slideA "pptbridge_lock_live_resize_btn"
  [void](Resize-DeckWindow $DeckPlain 820 520)
  Start-Sleep -Seconds 2
  $rect = Get-DeckWindowRect $DeckPlain
  $resizeShot = Join-Path $ArtifactsDir "$stamp-live-resized-window.png"
  Save-ObsScreenshot $socket $slideA $resizeShot
  $resizeInfo = Get-ImageInfo $resizeShot
  $resizeSettings = Invoke-ObsRequest $socket "GetInputSettings" @{ inputName = $slideA }
  Add-Result $results "PowerPoint window can resize without changing OBS output size" (
    $null -ne $rect -and $rect.width -lt 1000 -and $rect.height -lt 700 -and
    $resizeInfo.width -eq 1920 -and $resizeInfo.height -eq 1080 -and
    $resizeSettings.inputSettings.live_capture_resize_mode -eq "lock_canvas") (
    "PPT={0}x{1}; OBS={2}x{3}; mode={4}" -f
      $rect.width,$rect.height,$resizeInfo.width,$resizeInfo.height,$resizeSettings.inputSettings.live_capture_resize_mode)

  Press-InputButton $socket $slideA "pptbridge_follow_live_resize_btn"
  $followSettings = Invoke-ObsRequest $socket "GetInputSettings" @{ inputName = $slideA }
  Press-InputButton $socket $slideA "pptbridge_lock_live_resize_btn"
  $lockSettings = Invoke-ObsRequest $socket "GetInputSettings" @{ inputName = $slideA }
  Add-Result $results "Both live resize modes persist" (
    $followSettings.inputSettings.live_capture_resize_mode -eq "fit_window" -and
    $lockSettings.inputSettings.live_capture_resize_mode -eq "lock_canvas") (
    "follow={0}; lock={1}" -f
      $followSettings.inputSettings.live_capture_resize_mode,$lockSettings.inputSettings.live_capture_resize_mode)

  Press-InputButton $socket $slideA "pptbridge_reattach_live_btn"
  Start-Sleep -Seconds 3
  Add-Result $results "Manual live reattach keeps session alive" (@(Get-DeckSession $DeckPlain).Count -eq 1) ""

  $layoutHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($layout in @("balanced", "large_preview", "large_notes", "compact", "confidence_monitor")) {
    Set-InputSettings $socket $presenterA @{
      presenter_layout = $layout
      presenter_preview_scale_mode = "fit"
      presenter_notes_font_size = 18.0
      presenter_notes_zoom_percent = 115.0
      presenter_side_panel_width_percent = 110.0
      presenter_show_cue_list = $true
    }
    Start-Sleep -Milliseconds 650
    $layoutShot = Join-Path $ArtifactsDir "$stamp-presenter-$layout.png"
    Save-ObsScreenshot $socket $presenterA $layoutShot
    [void]$layoutHashes.Add((Get-FileHashText $layoutShot))
  }
  Add-Result $results "All five Presenter layouts render distinctly" ($layoutHashes.Count -eq 5) (
    "distinctHashes={0}" -f $layoutHashes.Count)

  $scaleHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($scaleMode in @("fit", "fill", "crop")) {
    Set-InputSettings $socket $presenterA @{
      presenter_layout = "balanced"
      presenter_preview_scale_mode = $scaleMode
      presenter_preview_scale_percent = 135.0
      presenter_preview_position_x = 12.0
      presenter_preview_position_y = -8.0
      presenter_notes_area_percent = 125.0
      presenter_notes_position_y = 8.0
    }
    Start-Sleep -Milliseconds 650
    $scaleShot = Join-Path $ArtifactsDir "$stamp-presenter-scale-$scaleMode.png"
    Save-ObsScreenshot $socket $presenterA $scaleShot
    [void]$scaleHashes.Add((Get-FileHashText $scaleShot))
  }
  Add-Result $results "Presenter fit fill crop modes render" ($scaleHashes.Count -ge 2) (
    "distinctHashes={0}" -f $scaleHashes.Count)

  Set-InputSettings $socket $presenterA @{
    presenter_background_color = 0x00382412
    presenter_background_image_path = $staticShot
    presenter_background_image_mode = "watermark"
    presenter_background_image_opacity_percent = 35.0
  }
  Start-Sleep -Seconds 1
  $backgroundShot = Join-Path $ArtifactsDir "$stamp-presenter-background.png"
  Save-ObsScreenshot $socket $presenterA $backgroundShot
  Add-Result $results "Presenter background image/color render" (
    (Get-ImageInfo $backgroundShot).bytes -gt 5000 -and
    (Get-FileHashText $backgroundShot) -ne (Get-FileHashText $presenterShot)) ""

  Press-InputButton $socket $presenterA "pptbridge_first_btn"
  [void](Wait-DeckSlide $DeckPlain 1)
  Press-InputButton $socket $presenterA "pptbridge_cue_toggle_current_btn"
  Press-InputButton $socket $presenterA "pptbridge_cue_toggle_next_btn"
  $cuePath = [IO.Path]::ChangeExtension($DeckPlain, ".pptbridge-cues.txt")
  Remove-Item -LiteralPath $cuePath -Force -ErrorAction SilentlyContinue
  Press-InputButton $socket $presenterA "pptbridge_export_cue_list_btn"
  Start-Sleep -Seconds 1
  $cueExported = Test-Path -LiteralPath $cuePath -PathType Leaf
  $cueText = if ($cueExported) { Get-Content -LiteralPath $cuePath -Raw } else { "" }
  Press-InputButton $socket $presenterA "pptbridge_cue_clear_checks_btn"
  Add-Result $results "Cue toggle clear and export work" (
    $cueExported -and $cueText.Length -gt 20) (
    "path={0}; bytes={1}" -f $cuePath,$cueText.Length)

  $expectedFeedback = @(
    "/pptbridge/status/current",
    "/pptbridge/status/total",
    "/pptbridge/status/title",
    "/pptbridge/status/next_title",
    "/pptbridge/status/deck_name",
    "/pptbridge/status/deck_path",
    "/pptbridge/status/source_name",
    "/pptbridge/status/error",
    "/pptbridge/status/timer",
    "/pptbridge/status/live",
    "/pptbridge/status/loading",
    "/pptbridge/status/loaded",
    "/pptbridge/status/black",
    "/pptbridge/status/cue_current_checked",
    "/pptbridge/status/cue_next_checked",
    "/pptbridge/status/cue_checked_count"
  )
  $feedbackReceiver = [Net.Sockets.UdpClient]::new($OscFeedbackPort)
  try {
    Set-InputSettings $socket $presenterA @{
      pptbridge_osc_feedback_enabled = $true
      pptbridge_osc_feedback_host = "127.0.0.1"
      pptbridge_osc_feedback_port = $OscFeedbackPort
    }
    Press-InputButton $socket $presenterA "pptbridge_send_osc_status_btn"
    $feedbackFound = Receive-OscAddresses $feedbackReceiver $expectedFeedback
    $feedbackMissing = @($expectedFeedback | Where-Object { $feedbackFound -notcontains $_ })
    Add-Result $results "OSC feedback sends all 16 status addresses" ($feedbackMissing.Count -eq 0) (
      "received={0}; missing={1}" -f $feedbackFound.Count,($feedbackMissing -join ","))
  } finally {
    $feedbackReceiver.Dispose()
  }

  $animationSettings = $baseSlideSettings.Clone()
  $animationSettings.pptx_path = $DeckAnimation
  $animationSettings.use_live_powerpoint = $true
  $animationSettings.use_live_app_audio = $false
  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneB
    inputName = $slideB
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $true
    inputSettings = $animationSettings
  } | Out-Null
  $createdInputs.Add($slideB) | Out-Null
  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneB } | Out-Null
  Press-InputButton $socket $slideB "pptbridge_start_live_btn"
  $animationStarted = Wait-DeckStarted $DeckAnimation
  if ($animationStarted) {
    Start-Sleep -Seconds 3
    Press-InputButton $socket $slideB "pptbridge_first_btn"
    [void](Wait-DeckSlide $DeckAnimation 1)
    Press-InputButton $socket $slideB "pptbridge_next_btn"
    $animationReachedSlide = Wait-DeckSlide $DeckAnimation 2
    Start-Sleep -Seconds 1
    $animationBefore = Join-Path $ArtifactsDir "$stamp-animation-before.png"
    $animationAfter = Join-Path $ArtifactsDir "$stamp-animation-after.png"
    Save-ObsScreenshot $socket $slideB $animationBefore
    $animationBeforeSession = @(Get-DeckSession $DeckAnimation)
    $animationClickBefore = if ($animationBeforeSession.Count -eq 1) {
      [int]$animationBeforeSession[0].clickIndex
    } else {
      -1
    }
    Press-InputButton $socket $slideB "pptbridge_next_btn"
    $animationClickAdvanced = Wait-Until {
      $session = @(Get-DeckSession $DeckAnimation)
      $session.Count -eq 1 -and
      [int]$session[0].current -eq 2 -and
      [int]$session[0].clickIndex -gt $animationClickBefore
    } -TimeoutSeconds 12 -PollMilliseconds 150
    Start-Sleep -Milliseconds 750
    Save-ObsScreenshot $socket $slideB $animationAfter
    $animationAfterSession = @(Get-DeckSession $DeckAnimation)
    $animationPosition = if ($animationAfterSession.Count -eq 1) {
      [int]$animationAfterSession[0].current
    } else {
      0
    }
    $animationClickAfter = if ($animationAfterSession.Count -eq 1) {
      [int]$animationAfterSession[0].clickIndex
    } else {
      -1
    }
    $animationImageChanged = (Get-FileHashText $animationBefore) -ne (Get-FileHashText $animationAfter)
    Add-Result $results "True live mode renders an in-slide animation step" (
      $animationReachedSlide -and $animationClickAdvanced -and
      $animationPosition -eq 2 -and $animationImageChanged) (
      "reachedSlide={0}; slide={1}; click={2}->{3}; imageChanged={4}" -f
        $animationReachedSlide,$animationPosition,
        $animationClickBefore,$animationClickAfter,$animationImageChanged)
  } else {
    Add-Result $results "True live mode renders an in-slide animation step" $false "Animation slideshow did not start"
  }
  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneA } | Out-Null

  $mediaSettings = $baseSlideSettings.Clone()
  $mediaSettings.pptx_path = $DeckMedia
  $mediaSettings.use_live_powerpoint = $true
  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneB
    inputName = $slideMedia
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $true
    inputSettings = $mediaSettings
  } | Out-Null
  $createdInputs.Add($slideMedia) | Out-Null
  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneB } | Out-Null
  Press-InputButton $socket $slideMedia "pptbridge_start_live_btn"
  $mediaStarted = Wait-DeckStarted $DeckMedia
  if ($mediaStarted) {
    Start-Sleep -Seconds 3
    Press-InputButton $socket $slideMedia "pptbridge_last_btn"
    $mediaReachedLast = Wait-DeckSlide $DeckMedia 3
    Start-Sleep -Seconds 3
    $mediaShot = Join-Path $ArtifactsDir "$stamp-media-live.png"
    Save-ObsScreenshot $socket $slideMedia $mediaShot
    $mediaInfo = Get-ImageInfo $mediaShot
    Add-Result $results "Embedded-media deck stays live and renders" (
      $mediaReachedLast -and @(Get-DeckSession $DeckMedia).Count -eq 1 -and $mediaInfo.bytes -gt 5000) (
      "slide={0}; bytes={1}" -f (Get-DeckSlide $DeckMedia),$mediaInfo.bytes)

    $meterSocket = $null
    try {
      $meterSocket = Connect-Obs -Password $WebSocketPassword -EventSubscriptions 65536
      Press-InputButton $socket $slideMedia "pptbridge_next_btn"
      $liveAudioPeak = Collect-ObsMeterPeak $meterSocket $slideMedia 15
      Add-Result $results "Live PowerPoint embedded audio reaches OBS mixer" (
        [double]$liveAudioPeak.peak -gt 0.001) (
        "peak={0:N6}; inputs={1}" -f
          [double]$liveAudioPeak.peak,($liveAudioPeak.matchedInputs -join "; "))
    } catch {
      Add-Result $results "Live PowerPoint embedded audio reaches OBS mixer" $false $_.Exception.Message
    } finally {
      if ($meterSocket) {
        $meterSocket.Dispose()
      }
    }
  } else {
    Add-Result $results "Embedded-media deck stays live and renders" $false "Media slideshow did not start"
    Add-Result $results "Live PowerPoint embedded audio reaches OBS mixer" $false "Media slideshow did not start"
  }
  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneA } | Out-Null

  Add-Result $results "Multiple PowerPoint live decks run simultaneously" (
    @(Get-DeckSession $DeckPlain).Count -eq 1 -and
    @(Get-DeckSession $DeckAnimation).Count -eq 1 -and
    @(Get-DeckSession $DeckMedia).Count -eq 1) (
    "activeQADecks={0}" -f @((Get-PowerPointSessions | Where-Object {
      $_.path -in @($DeckPlain,$DeckAnimation,$DeckMedia)
    })).Count)

  $aliasPath = (Split-Path -Parent $DeckPlain) + "\.\" + (Split-Path -Leaf $DeckPlain)
  $aliasSettings = $baseSlideSettings.Clone()
  $aliasSettings.pptx_path = $aliasPath
  $aliasSettings.use_live_powerpoint = $true
  $aliasSettings.use_live_app_audio = $false
  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneA
    inputName = $slideAlias
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $true
    inputSettings = $aliasSettings
  } | Out-Null
  $createdInputs.Add($slideAlias) | Out-Null

  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneA } | Out-Null
  Invoke-ObsRequest $socket "SetStudioModeEnabled" @{ studioModeEnabled = $true } | Out-Null
  Invoke-ObsRequest $socket "SetCurrentPreviewScene" @{ sceneName = $sceneB } | Out-Null
  Press-InputButton $socket $slideA "pptbridge_first_btn"
  Press-InputButton $socket $slideB "pptbridge_first_btn"
  [void](Wait-DeckSlide $DeckPlain 1)
  [void](Wait-DeckSlide $DeckAnimation 1)

  $clickerNext = Invoke-ClickerProbe "PAGEDOWN"
  $clickerProgramAdvanced = Wait-DeckSlide $DeckPlain 2
  $previewStayed = (Get-DeckSlide $DeckAnimation) -eq 1
  Add-Result $results "Clicker targets Program scene, not Studio Preview" (
    $clickerProgramAdvanced -and $previewStayed) (
    "program={0}; preview={1}" -f (Get-DeckSlide $DeckPlain),(Get-DeckSlide $DeckAnimation))
  Add-Result $results "PageDown clicker is swallowed by OBS capture" (
    $clickerNext.foregroundWasProbe -and
    $clickerNext.keyDownCount -eq 0 -and $clickerNext.keyUpCount -eq 0 -and
    [string]::IsNullOrEmpty([string]$clickerNext.capturedText)) (
    $clickerNext | ConvertTo-Json -Compress)
  Add-Result $results "Canonical duplicate source receives one click only" ((Get-DeckSlide $DeckPlain) -eq 2) (
    "current={0}" -f (Get-DeckSlide $DeckPlain))

  $clickerPrevious = Invoke-ClickerProbe "PAGEUP"
  $clickerPreviousWorked = Wait-DeckSlide $DeckPlain 1
  Add-Result $results "PageUp clicker moves back and is swallowed" (
    $clickerPreviousWorked -and $clickerPrevious.foregroundWasProbe -and
    $clickerPrevious.keyDownCount -eq 0 -and $clickerPrevious.keyUpCount -eq 0) (
    $clickerPrevious | ConvertTo-Json -Compress)

  foreach ($freeKey in @("1", "2", "LEFT", "RIGHT", "SPACE")) {
    $beforeFreeKey = Get-DeckSlide $DeckPlain
    $freeProbe = Invoke-ClickerProbe $freeKey
    Start-Sleep -Milliseconds 250
    $afterFreeKey = Get-DeckSlide $DeckPlain
    $expectedText = if ($freeKey -in @("1", "2")) { $freeKey } else { "" }
    $textPassed = if ($freeKey -in @("1", "2")) {
      [string]$freeProbe.capturedText -eq $expectedText
    } else {
      $freeProbe.keyDownCount -gt 0 -and $freeProbe.keyUpCount -gt 0
    }
    Add-Result $results "Normal key $freeKey remains available to focused app" (
      $freeProbe.foregroundWasProbe -and $textPassed -and $beforeFreeKey -eq $afterFreeKey) (
      "probe={0}; slideBefore={1}; slideAfter={2}" -f
        ($freeProbe | ConvertTo-Json -Compress),$beforeFreeKey,$afterFreeKey)
  }

  Press-InputButton $socket $slideA "pptbridge_first_btn"
  [void](Wait-DeckSlide $DeckPlain 1)
  Send-OscNoArg "/pptbridge/next" $OscPort
  $oscNext = Wait-DeckSlide $DeckPlain 2
  Send-OscNoArg "/pptbridge/previous" $OscPort
  $oscPrevious = Wait-DeckSlide $DeckPlain 1
  Send-OscNoArg "/pptbridge/last" $OscPort
  $oscLast = Wait-DeckSlide $DeckPlain $plainLastSlide 30
  Send-OscNoArg "/pptbridge/first" $OscPort
  $oscFirst = Wait-DeckSlide $DeckPlain 1
  $oscBeforeBlack = Join-Path $ArtifactsDir "$stamp-osc-black-before.png"
  $oscAfterBlack = Join-Path $ArtifactsDir "$stamp-osc-black-after.png"
  Save-ObsScreenshot $socket $slideA $oscBeforeBlack
  Send-OscNoArg "/pptbridge/black" $OscPort
  Start-Sleep -Seconds 1
  Save-ObsScreenshot $socket $slideA $oscAfterBlack
  $oscBlack = (Get-FileHashText $oscBeforeBlack) -ne (Get-FileHashText $oscAfterBlack)
  Send-OscNoArg "/pptbridge/black" $OscPort
  Send-OscNoArg "/pptbridge/reload" $OscPort
  Start-Sleep -Seconds 3
  $oscAlive = $null -ne (Invoke-ObsRequest $socket "GetVersion")
  Add-Result $results "All six OSC controls are accepted" (
    $oscNext -and $oscPrevious -and $oscLast -and $oscFirst -and $oscBlack -and $oscAlive) (
    "next={0}; previous={1}; last={2}; first={3}; black={4}; reloadAlive={5}" -f
      $oscNext,$oscPrevious,$oscLast,$oscFirst,$oscBlack,$oscAlive)

  Close-DeckSlideShow $DeckPlain
  $manualCloseObserved = Wait-DeckStopped $DeckPlain 12
  $autoRecovered = Wait-DeckStarted $DeckPlain 55
  Add-Result $results "Unexpected slideshow close auto-recovers" (
    $manualCloseObserved -and $autoRecovered) (
    "closeObserved={0}; recovered={1}" -f $manualCloseObserved,$autoRecovered)

  Press-InputButton $socket $slideA "pptbridge_stop_live_btn"
  $manualStopped = Wait-DeckStopped $DeckPlain
  Start-Sleep -Seconds 14
  $manualStopStayedStopped = @(Get-DeckSession $DeckPlain).Count -eq 0
  Add-Result $results "Manual STOP suppresses auto-recovery" (
    $manualStopped -and $manualStopStayedStopped) (
    "stopped={0}; stayedStopped={1}" -f $manualStopped,$manualStopStayedStopped)

  $racePassed = $true
  for ($race = 1; $race -le 3; $race++) {
    Press-InputButton $socket $slideA "pptbridge_start_live_btn"
    Start-Sleep -Milliseconds 180
    Press-InputButton $socket $slideA "pptbridge_stop_live_btn"
    Start-Sleep -Milliseconds 180
    Press-InputButton $socket $slideA "pptbridge_start_live_btn"
    if (-not (Wait-DeckStarted $DeckPlain 55)) {
      $racePassed = $false
      break
    }
    Press-InputButton $socket $slideA "pptbridge_stop_live_btn"
    if (-not (Wait-DeckStopped $DeckPlain 30)) {
      $racePassed = $false
      break
    }
  }
  Add-Result $results "Rapid Start Stop Start ordering is deterministic" $racePassed "cycles=3"

  $stressPassed = $true
  $stressDurations = [Collections.Generic.List[string]]::new()
  for ($cycle = 1; $cycle -le $StressCycles; $cycle++) {
    $cycleWatch = [Diagnostics.Stopwatch]::StartNew()
    Press-InputButton $socket $slideA "pptbridge_start_live_btn"
    if (-not (Wait-DeckStarted $DeckPlain)) {
      $stressPassed = $false
      $stressDurations.Add("$cycle:start-timeout") | Out-Null
      break
    }
    Press-InputButton $socket $slideA "pptbridge_stop_live_btn"
    if (-not (Wait-DeckStopped $DeckPlain)) {
      $stressPassed = $false
      $stressDurations.Add("$cycle:stop-timeout") | Out-Null
      break
    }
    $cycleWatch.Stop()
    $stressDurations.Add(("{0}:{1:N1}s" -f $cycle,$cycleWatch.Elapsed.TotalSeconds)) | Out-Null
  }
  Add-Result $results "$StressCycles repeated live Start Stop cycles pass" $stressPassed ($stressDurations -join ", ")

  $autoSettings = $baseSlideSettings.Clone()
  $autoSettings.auto_start_live_powerpoint = $true
  $autoSettings.use_live_powerpoint = $true
  Invoke-ObsRequest $socket "CreateInput" @{
    sceneName = $sceneAuto
    inputName = $slideAuto
    inputKind = "pptbridge_slide_source"
    sceneItemEnabled = $true
    inputSettings = $autoSettings
  } | Out-Null
  $createdInputs.Add($slideAuto) | Out-Null
  Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneAuto } | Out-Null
  $autoStarted = Wait-DeckStarted $DeckPlain
  Add-Result $results "Auto Start opens PowerPoint live mode" $autoStarted ""
  Press-InputButton $socket $slideAuto "pptbridge_stop_live_btn"
  [void](Wait-DeckStopped $DeckPlain)

  $compatibilityIndex = 0
  foreach ($compatibilityDeck in $CompatibilityDecks) {
    $compatibilityIndex += 1
    $compatibilityName = "$prefix Compatibility $compatibilityIndex"
    $compatibilityFile = Split-Path -Leaf $compatibilityDeck
    $compatibilitySceneItemId = 0
    $compatibilityWatch = [Diagnostics.Stopwatch]::StartNew()
    $compatibilityPassed = $false
    $compatibilityDetails = ""
    try {
      Close-DeckSlideShow $compatibilityDeck
      $compatibilitySettings = $baseSlideSettings.Clone()
      $compatibilitySettings.pptx_path = $compatibilityDeck
      $compatibilitySettings.use_live_powerpoint = $true
      $compatibilitySettings.auto_start_live_powerpoint = $true
      $compatibilitySettings.use_live_app_audio = $false
      $compatibilitySettings.auto_recover_live = $false
      $compatibilityCreate = Invoke-ObsRequest $socket "CreateInput" @{
        sceneName = $sceneInvalid
        inputName = $compatibilityName
        inputKind = "pptbridge_slide_source"
        sceneItemEnabled = $true
        inputSettings = $compatibilitySettings
      }
      $compatibilitySceneItemId = [int]$compatibilityCreate.sceneItemId
      $createdInputs.Add($compatibilityName) | Out-Null
      Invoke-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneInvalid } | Out-Null

      $compatibilityStarted = Wait-DeckStarted $compatibilityDeck $CompatibilityStartTimeoutSeconds
      $compatibilityWatch.Stop()
      if (-not $compatibilityStarted) {
        throw "Live slideshow did not start within $CompatibilityStartTimeoutSeconds seconds."
      }

      Start-Sleep -Seconds 4
      $compatibilitySession = @(Get-DeckSession $compatibilityDeck)[0]
      $compatibilityShot = Join-Path $ArtifactsDir (
        "$stamp-compat-{0:D2}-{1}.png" -f $compatibilityIndex,
          ([IO.Path]::GetFileNameWithoutExtension($compatibilityDeck) -replace '[^A-Za-z0-9_-]','_'))
      Save-ObsScreenshot $socket $compatibilityName $compatibilityShot
      $compatibilityImage = Get-ImageInfo $compatibilityShot
      $compatibilityDarkRatio = Get-DarkPixelRatio $compatibilityShot
      $compatibilityRenderOk =
        $compatibilityImage.width -eq 1920 -and
        $compatibilityImage.height -eq 1080 -and
        $compatibilityImage.bytes -gt 5000 -and
        $compatibilityDarkRatio -lt 0.995

      $compatibilityNavigationOk = $true
      if ([int]$compatibilitySession.total -gt 1) {
        Press-InputButton $socket $compatibilityName "pptbridge_last_btn"
        $lastReached = Wait-DeckSlide $compatibilityDeck ([int]$compatibilitySession.total) 20
        Press-InputButton $socket $compatibilityName "pptbridge_prev_btn"
        $previousReached = Wait-DeckSlide $compatibilityDeck ([int]$compatibilitySession.total - 1) 20
        $compatibilityNavigationOk = $lastReached -and $previousReached
      } else {
        Press-InputButton $socket $compatibilityName "pptbridge_next_btn"
        Start-Sleep -Seconds 1
        $compatibilityNavigationOk =
          @(Get-DeckSession $compatibilityDeck).Count -eq 1 -and
          (Get-DeckSlide $compatibilityDeck) -eq 1
      }

      Press-InputButton $socket $compatibilityName "pptbridge_stop_live_btn"
      $compatibilityStopped = Wait-DeckStopped $compatibilityDeck
      $obsAlive = $null -ne (Invoke-ObsRequest $socket "GetVersion")
      $compatibilityPassed =
        $compatibilityRenderOk -and $compatibilityNavigationOk -and
        $compatibilityStopped -and $obsAlive
      $compatibilityDetails =
        "slides={0}; start={1:N2}s; image={2}x{3}/{4} bytes; dark={5:N3}; navigation={6}; stopped={7}" -f
          $compatibilitySession.total,$compatibilityWatch.Elapsed.TotalSeconds,
          $compatibilityImage.width,$compatibilityImage.height,$compatibilityImage.bytes,
          $compatibilityDarkRatio,$compatibilityNavigationOk,$compatibilityStopped
    } catch {
      $compatibilityWatch.Stop()
      $compatibilityDetails = "start={0:N2}s; {1}" -f
        $compatibilityWatch.Elapsed.TotalSeconds,$_.Exception.Message
    } finally {
      Try-ObsRequest $socket "SetCurrentProgramScene" @{ sceneName = $sceneA } | Out-Null
      try {
        Close-DeckSlideShow $compatibilityDeck
      } catch {
      }
      if ($compatibilitySceneItemId -gt 0) {
        Try-ObsRequest $socket "RemoveSceneItem" @{
          sceneName = $sceneInvalid
          sceneItemId = $compatibilitySceneItemId
        } | Out-Null
      }
      Try-ObsRequest $socket "RemoveInput" @{ inputName = $compatibilityName } | Out-Null
      [void]$createdInputs.Remove($compatibilityName)
    }
    Add-Result $results "Compatibility live deck: $compatibilityFile" `
      $compatibilityPassed $compatibilityDetails
  }

  $invalidDir = Join-Path $ArtifactsDir "invalid-inputs"
  New-Item -ItemType Directory -Path $invalidDir -Force | Out-Null
  $emptyPath = Join-Path $invalidDir "empty.pptx"
  $corruptPath = Join-Path $invalidDir "corrupt.pptx"
  $unsupportedPath = Join-Path $invalidDir "unsupported.txt"
  $pdfPath = Join-Path $invalidDir "unsupported.pdf"
  [IO.File]::WriteAllBytes($emptyPath, [byte[]]@())
  [IO.File]::WriteAllText($corruptPath, "not a PowerPoint package")
  [IO.File]::WriteAllText($unsupportedPath, "unsupported")
  [IO.File]::WriteAllText($pdfPath, "%PDF-1.4`nunsupported on Windows")
  $invalidCases = @(
    @{ label = "missing"; path = (Join-Path $invalidDir "missing.pptx") },
    @{ label = "empty"; path = $emptyPath },
    @{ label = "corrupt"; path = $corruptPath },
    @{ label = "unsupported-extension"; path = $unsupportedPath },
    @{ label = "pdf-unsupported"; path = $pdfPath }
  )
  foreach ($invalidCase in $invalidCases) {
    $invalidName = "$prefix Invalid $($invalidCase.label)"
    $invalidSettings = $baseSlideSettings.Clone()
    $invalidSettings.pptx_path = $invalidCase.path
    $invalidSettings.use_live_powerpoint = $false
    Invoke-ObsRequest $socket "CreateInput" @{
      sceneName = $sceneInvalid
      inputName = $invalidName
      inputKind = "pptbridge_slide_source"
      sceneItemEnabled = $true
      inputSettings = $invalidSettings
    } | Out-Null
    $createdInputs.Add($invalidName) | Out-Null
    Start-Sleep -Milliseconds 900
    $invalidShot = Join-Path $ArtifactsDir "$stamp-invalid-$($invalidCase.label).png"
    Save-ObsScreenshot $socket $invalidName $invalidShot
    $invalidInfo = Get-ImageInfo $invalidShot
    $obsStillAlive = $null -ne (Invoke-ObsRequest $socket "GetVersion")
    Add-Result $results "Invalid input $($invalidCase.label) is safe" (
      $invalidInfo.width -eq 1920 -and $invalidInfo.height -eq 1080 -and $obsStillAlive) (
      "{0}x{1}; OBS alive={2}" -f $invalidInfo.width,$invalidInfo.height,$obsStillAlive)
  }

  Invoke-ObsRequest $socket "SetStudioModeEnabled" @{ studioModeEnabled = $false } | Out-Null
  $finalVersion = Invoke-ObsRequest $socket "GetVersion"
  Add-Result $results "OBS remains responsive after full suite" ($null -ne $finalVersion) ""
} catch {
  $unexpectedError = $_.Exception.ToString()
  Add-Result $results "Runtime suite completed without an unexpected exception" $false $unexpectedError
} finally {
  foreach ($deck in @($DeckPlain, $DeckAnimation, $DeckMedia) + @($CompatibilityDecks)) {
    try {
      Close-DeckSlideShow $deck
    } catch {
    }
  }

  if ($null -ne $socket) {
    for ($sceneIndex = $createdScenes.Count - 1; $sceneIndex -ge 0; $sceneIndex--) {
      Try-ObsRequest $socket "RemoveScene" @{ sceneName = $createdScenes[$sceneIndex] } | Out-Null
    }
    for ($inputIndex = $createdInputs.Count - 1; $inputIndex -ge 0; $inputIndex--) {
      Try-ObsRequest $socket "RemoveInput" @{ inputName = $createdInputs[$inputIndex] } | Out-Null
    }
    try {
      $socket.Dispose()
    } catch {
    }
  }
}

$passedCount = @($results | Where-Object passed).Count
$failed = @($results | Where-Object { -not $_.passed })
$report = [pscustomobject]@{
  runLabel = $RunLabel
  timestamp = (Get-Date).ToString("o")
  passed = ($failed.Count -eq 0)
  passedCount = $passedCount
  failedCount = $failed.Count
  artifactsDir = $ArtifactsDir
  decks = @{
    plain = $DeckPlain
    animation = $DeckAnimation
    media = $DeckMedia
    compatibility = @($CompatibilityDecks)
  }
  results = @($results)
  unexpectedError = $unexpectedError
}
$reportPath = Join-Path $ArtifactsDir "$stamp-$RunLabel-report.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 12
if (-not $report.passed) {
  exit 1
}
