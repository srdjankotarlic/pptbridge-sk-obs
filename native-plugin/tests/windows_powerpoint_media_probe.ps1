param(
  [Parameter(Mandatory = $true)]
  [string]$DeckPath,
  [int]$SlideNumber = 3,
  [int]$ShapeId = 0,
  [int]$PlaySeconds = 3,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DeckPath -PathType Leaf)) {
  throw "Deck does not exist: $DeckPath"
}
$DeckPath = (Resolve-Path -LiteralPath $DeckPath).Path

function Release-ComObjectQuietly {
  param($Value)
  if ($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
    try {
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Value)
    } catch {
    }
  }
}

$app = $null
$presentation = $null
$settings = $null
$show = $null
$view = $null
$slide = $null
$player = $null
$createdApp = $false
$ownsPresentation = $false
$ownsShow = $false

try {
  try {
    $app = [Runtime.InteropServices.Marshal]::GetActiveObject("PowerPoint.Application")
  } catch {
    $app = New-Object -ComObject PowerPoint.Application
    $createdApp = $true
  }
  $app.Visible = -1

  foreach ($candidate in @($app.Presentations)) {
    try {
      if ([string]::Equals(
          [IO.Path]::GetFullPath([string]$candidate.FullName),
          $DeckPath,
          [StringComparison]::OrdinalIgnoreCase)) {
        $presentation = $candidate
        break
      }
    } catch {
    }
  }
  if ($null -eq $presentation) {
    $presentation = $app.Presentations.Open($DeckPath, $true, $false, $true)
    $ownsPresentation = $true
  }

  foreach ($candidate in @($app.SlideShowWindows)) {
    try {
      if ([string]::Equals(
          [IO.Path]::GetFullPath([string]$candidate.Presentation.FullName),
          $DeckPath,
          [StringComparison]::OrdinalIgnoreCase)) {
        $show = $candidate
        break
      }
    } catch {
    }
  }
  if ($null -eq $show) {
    $settings = $presentation.SlideShowSettings
    $settings.ShowType = 2
    $settings.LoopUntilStopped = $false
    $show = $settings.Run()
    $ownsShow = $true
    Start-Sleep -Seconds 2
  }

  $view = $show.View
  $slideCount = [int]$presentation.Slides.Count
  if ($SlideNumber -lt 1 -or $SlideNumber -gt $slideCount) {
    throw "SlideNumber $SlideNumber is outside 1..$slideCount."
  }
  $view.GotoSlide($SlideNumber, 0)
  Start-Sleep -Milliseconds 700

  $slide = $presentation.Slides.Item($SlideNumber)
  $shapeRecords = [Collections.Generic.List[object]]::new()
  $selectedShapeId = $ShapeId
  foreach ($shape in @($slide.Shapes)) {
    try {
      $mediaType = 0
      try { $mediaType = [int]$shape.MediaType } catch {}
      $playOnEntry = $null
      try { $playOnEntry = [bool]$shape.AnimationSettings.PlaySettings.PlayOnEntry } catch {}
      $shapeRecords.Add([pscustomobject]@{
        id = [int]$shape.Id
        name = [string]$shape.Name
        type = [int]$shape.Type
        mediaType = $mediaType
        playOnEntry = $playOnEntry
      }) | Out-Null
      if ($selectedShapeId -eq 0 -and $mediaType -ne 0) {
        $selectedShapeId = [int]$shape.Id
      }
    } finally {
      Release-ComObjectQuietly $shape
    }
  }

  $clickIndexBefore = -1
  $clickCountBefore = -1
  try { $clickIndexBefore = [int]$view.GetClickIndex() } catch {}
  try { $clickCountBefore = [int]$view.GetClickCount() } catch {}

  $states = [Collections.Generic.List[object]]::new()
  $playerError = ""
  if ($selectedShapeId -gt 0) {
    try {
      $player = $view.Player($selectedShapeId)
      $states.Add([pscustomobject]@{
        elapsedMs = 0
        state = [int]$player.State
        position = [double]$player.CurrentPosition
      }) | Out-Null
      $player.Play()
      $watch = [Diagnostics.Stopwatch]::StartNew()
      while ($watch.Elapsed.TotalSeconds -lt $PlaySeconds) {
        Start-Sleep -Milliseconds 250
        $states.Add([pscustomobject]@{
          elapsedMs = [int]$watch.ElapsedMilliseconds
          state = [int]$player.State
          position = [double]$player.CurrentPosition
        }) | Out-Null
      }
    } catch {
      $playerError = $_.Exception.Message
    }
  } else {
    $playerError = "No media shape was found on slide $SlideNumber."
  }

  $payload = [pscustomobject]@{
    deck = $DeckPath
    slide = $SlideNumber
    slideCount = $slideCount
    clickIndex = $clickIndexBefore
    clickCount = $clickCountBefore
    selectedShapeId = $selectedShapeId
    playerError = $playerError
    shapes = @($shapeRecords)
    states = @($states)
  }
  $json = $payload | ConvertTo-Json -Depth 7
  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
  }
  $json
} finally {
  if ($ownsShow -and $null -ne $show) {
    try { $show.View.Exit() } catch {}
  }
  if ($ownsPresentation -and $null -ne $presentation) {
    try { $presentation.Close() } catch {}
  }
  if ($createdApp -and $null -ne $app) {
    try {
      if ([int]$app.Presentations.Count -eq 0 -and [int]$app.SlideShowWindows.Count -eq 0) {
        $app.Quit()
      }
    } catch {
    }
  }
  Release-ComObjectQuietly $player
  Release-ComObjectQuietly $slide
  Release-ComObjectQuietly $view
  Release-ComObjectQuietly $show
  Release-ComObjectQuietly $settings
  Release-ComObjectQuietly $presentation
  Release-ComObjectQuietly $app
}
