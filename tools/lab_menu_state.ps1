param([Parameter(Mandatory = $true)][int]$GameProcessId)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
}
$lab = Split-Path (Split-Path $process.Path -Parent) -Parent
if (-not (Test-Path -LiteralPath (Join-Path $lab '.isaac-lan-lab') -PathType Leaf)) {
    throw 'A marked isolated game is required.'
}
$profile = Get-Content -Raw -LiteralPath (Join-Path $lab 'game-profile.json') | ConvertFrom-Json
$layout = switch ($profile.game_build) {
    '1.7.9b.J835' { @{ manager = 0x7fd680; menus = 0x7fd688; dialogs = 0x4a268; page = 0x38; selected = 0x80fb0; fileState = 0x634; fileSelected = 0x638 } }
    '1.9.7.19.J510' { @{ manager = 0x89a0d4; menus = 0x89a8e4; dialogs = 0x4d074; page = 0x40; selected = 0xb94; fileState = 0x2f4; fileSelected = 0x2f8 } }
    default { throw 'Unsupported isolated menu layout.' }
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanMenuRead {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr handle,IntPtr address,byte[] data,UIntPtr size,out UIntPtr read);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$handle = [LanMenuRead]::OpenProcess(0x0010, $false, $GameProcessId)
if ($handle -eq [IntPtr]::Zero) {
    throw 'Cannot read the owned fixture.'
}
function Read32([long]$address) {
    $bytes = New-Object byte[] 4
    [UIntPtr]$count = [UIntPtr]::Zero
    if (-not [LanMenuRead]::ReadProcessMemory($handle, [IntPtr]$address, $bytes, [UIntPtr]([uint32]4), [ref]$count)) {
        throw ('Cannot read menu state at 0x{0:X} for owned PID {1}.' -f $address, $GameProcessId)
    }
    return [BitConverter]::ToUInt32($bytes, 0)
}
try {
    $base = $process.MainModule.BaseAddress.ToInt64()
    $manager = Read32 ($base + $layout.manager)
    $menu = Read32 ($base + $layout.menus)
    # The menu allocation is absent during native startup and gameplay.
    # Report an unready menu instead of dereferencing a null pointer.
    $snapshot = [ordered]@{gameState = 0; menu = -1; selected = -1; fileState = -1; fileSelected = -1; dialogs = 0 }
    if ($manager -ne 0) {
        $snapshot.gameState = Read32 ($manager + 8)
        $snapshot.dialogs = Read32 ($manager + $layout.dialogs)
    }
    if ($menu -ne 0) {
        $snapshot.menu = Read32 ($menu + $layout.page)
        $snapshot.selected = Read32 ($menu + $layout.selected)
        $snapshot.fileState = Read32 ($menu + $layout.fileState)
        $snapshot.fileSelected = Read32 ($menu + $layout.fileSelected)
    }
    $snapshot | ConvertTo-Json
} finally {
    [void][LanMenuRead]::CloseHandle($handle)
}
