param(
    [Parameter(Mandatory=$true)][int]$GameProcessId,
    [ValidateSet('Capture','Keys','PostKeys','Close')][string]$Action = 'Capture',
    [string]$Value = '',
    [string]$ImagePath = ''
)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Refusing to control a process outside the isolated lab.'
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanLabWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint kind);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@
if ($Action -eq 'PostKeys') {
    $keys = @{ '{ENTER}'=13; '{SPACE}'=32; '{ESC}'=27; '{UP}'=38; '{DOWN}'=40; '{LEFT}'=37; '{RIGHT}'=39; '{CONSOLE}'=192; '{BACKSPACE}'=8; '.'=190; 'W'=87; 'A'=65; 'S'=83; 'D'=68 }
    if ($keys.ContainsKey($Value)) { $key = $keys[$Value] }
    elseif ($Value -match '^[0-9A-Z]$') { $key = [int][char]$Value }
    else { throw 'Unsupported direct lab key.' }
    $scan = [LanLabWindow]::MapVirtualKey($key, 0)
    [long]$flags = 1 -bor ($scan -shl 16)
    if ($key -ge 37 -and $key -le 40) { $flags = $flags -bor 16777216L }
    [void][LanLabWindow]::PostMessage($process.MainWindowHandle, 0x100, [IntPtr]$key, [IntPtr]$flags)
    Start-Sleep -Milliseconds 100
    $flags = $flags -bor 3221225472L
    [void][LanLabWindow]::PostMessage($process.MainWindowHandle, 0x101, [IntPtr]$key, [IntPtr]$flags)
    exit
}
if ($Action -eq 'Close') {
    [void][LanLabWindow]::PostMessage($process.MainWindowHandle, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit(5000)) {
        $remaining = Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
        if ($remaining) {
            if ($remaining.Path -ne $process.Path) { throw 'The owned lab process identity changed.' }
            Stop-Process -Id $GameProcessId -Force
            if (-not $remaining.WaitForExit(5000)) { throw 'The owned lab process has not finished closing.' }
        }
    }
    exit
}
$shell = New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($GameProcessId)
[uint32]$oldForegroundId = 0
$foregroundThread = [LanLabWindow]::GetWindowThreadProcessId([LanLabWindow]::GetForegroundWindow(), [ref]$oldForegroundId)
$currentThread = [LanLabWindow]::GetCurrentThreadId()
[void][LanLabWindow]::AttachThreadInput($currentThread, $foregroundThread, $true)
[void][LanLabWindow]::ShowWindow($process.MainWindowHandle, 9)
[void][LanLabWindow]::SetForegroundWindow($process.MainWindowHandle)
[void][LanLabWindow]::AttachThreadInput($currentThread, $foregroundThread, $false)
Start-Sleep -Milliseconds 150
[uint32]$foregroundProcessId = 0
[void][LanLabWindow]::GetWindowThreadProcessId([LanLabWindow]::GetForegroundWindow(), [ref]$foregroundProcessId)
if ($foregroundProcessId -ne $GameProcessId) { throw 'The lab game is not in the foreground.' }
if ($Action -eq 'Keys') {
    $keys = @{ '{ENTER}'=13; '{SPACE}'=32; '{ESC}'=27; '{UP}'=38; '{DOWN}'=40; '{LEFT}'=37; '{RIGHT}'=39; '{CONSOLE}'=192; '{BACKSPACE}'=8; '.'=190; 'W'=87; 'A'=65; 'S'=83; 'D'=68 }
    if ($keys.ContainsKey($Value)) {
        $key = $keys[$Value]
        $scan = [LanLabWindow]::MapVirtualKey($key, 0)
        [uint32]$downFlags = 0
        if ($key -ge 37 -and $key -le 40) { $downFlags = 1 }
        [LanLabWindow]::keybd_event($key, $scan, $downFlags, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 500
        [LanLabWindow]::keybd_event($key, $scan, ($downFlags -bor 2), [UIntPtr]::Zero)
    } else { $shell.SendKeys($Value) }
} else {
    if (-not $ImagePath) { throw 'ImagePath is required.' }
    Add-Type -AssemblyName System.Drawing
    $rect = New-Object LanLabWindow+Rect
    [void][LanLabWindow]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
    $image = New-Object System.Drawing.Bitmap ($rect.R - $rect.L), ($rect.B - $rect.T)
    $graphics = [System.Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($rect.L, $rect.T, 0, 0, $image.Size)
        $image.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $image.Dispose() }
}
