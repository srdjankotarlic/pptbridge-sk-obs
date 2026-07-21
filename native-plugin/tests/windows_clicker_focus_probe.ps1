param(
  [ValidateSet("1", "2", "LEFT", "RIGHT", "SPACE", "PAGEUP", "PAGEDOWN")]
  [string]$Key = "PAGEDOWN",
  [int]$CloseAfterMilliseconds = 1400
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PptBridgeClickerProbeInput {
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int command);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);

  [DllImport("kernel32.dll")]
  public static extern uint GetCurrentThreadId();

  [DllImport("user32.dll")]
  public static extern bool AttachThreadInput(uint sourceThread, uint targetThread, bool attach);

  [DllImport("user32.dll")]
  public static extern IntPtr SetActiveWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern IntPtr SetFocus(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);
}
"@

function ConvertTo-VirtualKey {
  param([string]$Value)

  switch ($Value.ToUpperInvariant()) {
    "1" { return 0x31 }
    "2" { return 0x32 }
    "LEFT" { return 0x25 }
    "RIGHT" { return 0x27 }
    "SPACE" { return 0x20 }
    "PAGEUP" { return 0x21 }
    "PAGEDOWN" { return 0x22 }
  }
  throw "Unsupported probe key: $Value"
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$script:keyDownCount = 0
$script:keyUpCount = 0
$script:capturedText = ""
$script:foregroundWasProbe = $false
$script:foregroundWindow = 0

$form = [System.Windows.Forms.Form]::new()
$form.Text = "PPTBridge Clicker Focus Probe"
$form.TopMost = $true
$form.KeyPreview = $true
$form.StartPosition = "CenterScreen"
$form.Width = 440
$form.Height = 150

$textBox = [System.Windows.Forms.TextBox]::new()
$textBox.Left = 20
$textBox.Top = 28
$textBox.Width = 380
$form.Controls.Add($textBox)

$form.Add_KeyDown({
  $script:keyDownCount += 1
})
$form.Add_KeyUp({
  $script:keyUpCount += 1
})
$textBox.Add_KeyDown({
  $script:keyDownCount += 1
})
$textBox.Add_KeyUp({
  $script:keyUpCount += 1
})

$sendTimer = [System.Windows.Forms.Timer]::new()
$sendTimer.Interval = 450
$sendTimer.Add_Tick({
  $sendTimer.Stop()
  $foreground = [PptBridgeClickerProbeInput]::GetForegroundWindow()
  $foregroundThread = [PptBridgeClickerProbeInput]::GetWindowThreadProcessId($foreground, [IntPtr]::Zero)
  $currentThread = [PptBridgeClickerProbeInput]::GetCurrentThreadId()
  $attached = $false
  if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
    $attached = [PptBridgeClickerProbeInput]::AttachThreadInput($currentThread, $foregroundThread, $true)
  }
  try {
    [void][PptBridgeClickerProbeInput]::ShowWindowAsync($form.Handle, 9)
    [void][PptBridgeClickerProbeInput]::BringWindowToTop($form.Handle)
    [void][PptBridgeClickerProbeInput]::SetForegroundWindow($form.Handle)
    [void][PptBridgeClickerProbeInput]::SetActiveWindow($form.Handle)
    $form.Activate()
    $textBox.Focus()
    [void][PptBridgeClickerProbeInput]::SetFocus($textBox.Handle)
  } finally {
    if ($attached) {
      [void][PptBridgeClickerProbeInput]::AttachThreadInput($currentThread, $foregroundThread, $false)
    }
  }
  Start-Sleep -Milliseconds 120
  $script:foregroundWindow = [PptBridgeClickerProbeInput]::GetForegroundWindow().ToInt64()
  $script:foregroundWasProbe = $script:foregroundWindow -eq $form.Handle.ToInt64()
  $virtualKey = [byte](ConvertTo-VirtualKey $Key)
  [PptBridgeClickerProbeInput]::keybd_event($virtualKey, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 90
  [PptBridgeClickerProbeInput]::keybd_event($virtualKey, 0, 0x0002, [UIntPtr]::Zero)
})

$closeTimer = [System.Windows.Forms.Timer]::new()
$closeTimer.Interval = $CloseAfterMilliseconds
$closeTimer.Add_Tick({
  $closeTimer.Stop()
  $script:capturedText = $textBox.Text
  $form.Close()
})

$hardStopTimer = [System.Windows.Forms.Timer]::new()
$hardStopTimer.Interval = 5000
$hardStopTimer.Add_Tick({
  $hardStopTimer.Stop()
  $script:capturedText = $textBox.Text
  $form.Close()
})

$form.Add_Shown({
  $form.Activate()
  $textBox.Focus()
  $sendTimer.Start()
  $closeTimer.Start()
  $hardStopTimer.Start()
})

[System.Windows.Forms.Application]::Run($form)

[pscustomobject]@{
  key = $Key
  keyDownCount = $script:keyDownCount
  keyUpCount = $script:keyUpCount
  capturedText = $script:capturedText
  foregroundWasProbe = $script:foregroundWasProbe
  foregroundWindow = $script:foregroundWindow
} | ConvertTo-Json -Compress
