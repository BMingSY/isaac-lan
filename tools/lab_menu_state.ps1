param([Parameter(Mandatory = $true)][int]$GameProcessId)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
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
        throw 'Cannot read menu state.'
    }
    return [BitConverter]::ToUInt32($bytes, 0)
}
try {
    $base = $process.MainModule.BaseAddress.ToInt64()
    $manager = Read32 ($base + 0x87169c)
    $menu = Read32 ($base + 0x872a20)
    [ordered]@{gameState = (Read32 ($manager + 8)); menu = (Read32 ($menu + 0x40)); selected = (Read32 ($menu + 0xb94)); dialogs = (Read32 ($manager + 0x4d074)) } | ConvertTo-Json
} finally {
    [void][LanMenuRead]::CloseHandle($handle)
}
